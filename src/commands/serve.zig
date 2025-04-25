const std = @import("std");
const datetime = @import("datetime").datetime;
const zmpl = @import("zmpl");
const httpz = @import("httpz");

const OnoIgnore = @import("../OnoIgnore.zig");
const Task = @import("../Task.zig");
const DirWalker = @import("../DirWalker.zig");

const ls = @import("ls.zig");
const Sort = ls.Sort;
const Order = ls.Order;
const SortContext = ls.SortContext;

const createHelpScreenSection = @import("../help_screen.zig").createHelpScreenSection;

const help_screen = "ono serve [...paths] [-hrp]\n\n" ++
    "Parameters:\n" ++
    createHelpScreenSection(.{
        .{ "paths", "the folders and files to serve, default is current working directory" },
    }) ++ "\n\n" ++
    "Options:\n" ++
    createHelpScreenSection(.{
        .{ "-h, --help", "show this screen" },
        .{ "-r, --recursive", "serve tasks in all sub-directories recursively" },
        .{ "-p, --port <port>", "the tcp port to listen on" },
    });

pub const Error = error{ MissingArgument, UnknownFlag, BadPort };

pub const Flag = enum {
    init,
    help,
    recursive,
    port,

    pub fn fromShorthand(char: u8) ?Flag {
        return switch (char) {
            'h' => .help,
            'r' => .recursive,
            'p' => .port,
            else => null,
        };
    }
};

pub const Handler = struct {
    cached_at_timestamp: i64,
    files: []DirWalker.FileTask,
    all_tags: std.StringArrayHashMapUnmanaged(void),
    all_assignments: std.StringArrayHashMapUnmanaged(void),
};

pub fn exec(allocator: std.mem.Allocator, args_iterator: *std.process.ArgIterator, stdout_writer: anytype, stderr_writer: anytype) !void {
    _ = stderr_writer;

    var input_paths: std.ArrayListUnmanaged([]const u8) = .empty;
    defer input_paths.deinit(allocator);
    defer for (input_paths.items) |path| allocator.free(path);
    var input_show_help: bool = false;
    var input_recursive: bool = false;
    var input_port: ?u16 = null;

    var full_shorthand: ?[]const u8 = null;
    defer if (full_shorthand) |full| allocator.free(full);

    var shorthand: []const u8 = "";
    process_flag: switch (@as(Flag, .init)) {
        .init => {
            if (shorthand.len > 0) {
                defer shorthand = shorthand[1..];
                continue :process_flag Flag.fromShorthand(shorthand[0]) orelse return Error.UnknownFlag;
            }
            const next_arg = args_iterator.next() orelse break :process_flag;
            if (next_arg[0] == '-') {
                if (next_arg[1] == '-') {
                    continue :process_flag std.meta.stringToEnum(Flag, next_arg[2..]) orelse
                        return Error.UnknownFlag;
                }
                const duped_shorthand = try allocator.dupe(u8, next_arg);
                if (full_shorthand) |full| allocator.free(full);
                full_shorthand = duped_shorthand;
                shorthand = duped_shorthand[1..];
                continue :process_flag .init;
            }

            const duped = try allocator.dupe(u8, next_arg);
            errdefer allocator.free(duped);
            try input_paths.append(allocator, duped);
            continue :process_flag .init;
        },
        .help => {
            input_show_help = true;
            continue :process_flag .init;
        },
        .recursive => {
            input_recursive = true;
            continue :process_flag .init;
        },
        .port => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            input_port = std.fmt.parseInt(u16, next_arg, 10) catch return Error.BadPort;
            continue :process_flag .init;
        },
    }

    if (input_show_help) {
        _ = try stdout_writer.print("{s}\n", .{help_screen});
        return;
    }

    if (input_paths.items.len == 0) {
        try input_paths.append(allocator, "");
    }

    var file_tasks: std.ArrayListUnmanaged(DirWalker.FileTask) = .empty;
    defer file_tasks.deinit(allocator);
    defer for (file_tasks.items) |file_task| file_task.deinit(allocator);

    var dir_walker: DirWalker = .init(allocator, &file_tasks);
    defer dir_walker.deinit(allocator);

    dir_walker.filter = .{};

    for (input_paths.items) |path| {
        _ = std.fs.cwd().statFile(path) catch |e| switch (e) {
            error.IsDir => {
                if (!input_recursive) continue;

                var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
                defer dir.close();

                try dir_walker.walkDirectory(dir);
            },
            else => return e,
        };

        if (!std.mem.eql(u8, std.fs.path.extension(path), ".ono")) continue;

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        try dir_walker.addFileWithPath(file, path);
    }

    var all_tags: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer all_tags.deinit(allocator);

    var all_assignments: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer all_assignments.deinit(allocator);

    for (dir_walker.collector.*.items) |file_task| {
        for (file_task.task.tags) |tag| try all_tags.put(allocator, tag, {});
        if (file_task.task.maybe_assigned_to) |assigned_to| try all_assignments.put(allocator, assigned_to, {});
    }

    const cached_at_timestamp = std.time.milliTimestamp();

    var server: httpz.Server(Handler) = try .init(allocator, .{
        .address = "0.0.0.0",
        .port = 57800,
    }, .{
        .cached_at_timestamp = cached_at_timestamp,
        .files = file_tasks.items,
        .all_tags = all_tags,
        .all_assignments = all_assignments,
    });
    defer {
        server.stop();
        server.deinit();
    }

    var router = try server.router(.{});
    router.get("/", getHomePage, .{});
    router.get("/show", getTaskShow, .{});

    router.get("/resources/*", getResources, .{});

    const thread = try server.listenInNewThread();

    var ipv4: std.net.Address = .initIp4(undefined, 0);
    var socklen = ipv4.getOsSockLen();
    try std.posix.getsockname(server._listener.?, &ipv4.any, &socklen);
    try stdout_writer.print("Listen on {}\n", .{ipv4});

    thread.join();
}

fn createTaskObject(data: *zmpl.Data, file_task: DirWalker.FileTask) !*zmpl.Data.Value {
    const obj = try data.object();

    try obj.put("id", data.string(file_task.path));
    try obj.put("name", data.string(file_task.task.name));

    const tags = try data.array();
    for (file_task.task.tags) |tag| {
        try tags.append(data.string(tag));
    }

    try obj.put("tags", tags);

    try obj.put("priority", data.string(@tagName(file_task.task.priority)));
    try obj.put("assigned_to", if (file_task.task.maybe_assigned_to) |assigned_to| data.string(assigned_to) else data.string(""));
    try obj.put("due_by", data.string("n/a"));

    const notes = try data.array();
    for (file_task.task.notes) |note| {
        const note_obj = try data.object();

        try obj.put("attributed_to", if (note.maybe_attributed_to) |attributed_to| data.string(attributed_to) else data.string(""));
        try obj.put("note", if (note.maybe_note) |note_contents| data.string(note_contents) else data.string(""));

        const attachments = try data.array();
        for (note.attachments) |attachment_path| {
            try attachments.append(data.string(attachment_path));
        }

        try note_obj.put("attachments", attachments);

        try notes.append(note_obj);
    }

    try obj.put("notes", notes);
    try obj.put("num_notes", notes.count());

    return obj;
}

fn createCachedAtString(arena: std.mem.Allocator, data: *zmpl.Data, created_at_timestamp: i64) !*zmpl.Data.Value {
    const utc_datetime = datetime.Datetime.fromTimestamp(created_at_timestamp);

    return data.string(try utc_datetime.formatHttp(arena));
}

fn getHomePage(handler: Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const query_parameters = try req.query();

    const filter_query = query_parameters.get("filter_query") orelse "";
    const filter_tags_string = query_parameters.get("filter_tags") orelse "";
    const filter_assignment = query_parameters.get("filter_assignment") != null;
    const filter_assigned_to_string = query_parameters.get("filter_assigned_to");

    const sort_field_string = query_parameters.get("sort_field") orelse "name";
    const sort_order_string = query_parameters.get("sort_order") orelse "ascending";

    const sort_field = std.meta.stringToEnum(Sort, sort_field_string) orelse return {
        res.status = 400;
        res.body = "Bad Request";
        return;
    };

    const sort_order = std.meta.stringToEnum(Order, sort_order_string) orelse return {
        res.status = 400;
        res.body = "Bad Request";
        return;
    };

    var request_filter_tags: std.ArrayListUnmanaged([]const u8) = try .initCapacity(req.arena, std.mem.count(u8, filter_tags_string, ",") + 1);
    var tokenize_tags = std.mem.tokenizeAny(u8, filter_tags_string, ",");
    while (tokenize_tags.next()) |tag| request_filter_tags.appendAssumeCapacity(tag);

    const layout_template = zmpl.find("layouts/main") orelse {
        res.status = 500;
        res.body = "Internal server error";
        return;
    };

    const page_template = zmpl.find("home") orelse {
        res.status = 500;
        res.body = "Internal server error";
        return;
    };

    res.status = 200;

    var data: zmpl.Data = .init(req.arena);

    const body = try data.object();
    try body.put("cached_at_timestamp", try createCachedAtString(req.arena, &data, handler.cached_at_timestamp));

    try body.put("filter_query", data.string(filter_query));

    const filter_tags = try data.array();
    for (request_filter_tags.items) |filter_tag| {
        try filter_tags.append(data.string(filter_tag));
    }

    try body.put("filter_tags", filter_tags);

    try body.put("filter_assignment", data.boolean(filter_assignment));
    try body.put("filter_has_assigned_to", data.boolean(filter_assigned_to_string != null));
    if (filter_assigned_to_string) |assigned_to| {
        try body.put("filter_assigned_to", data.string(assigned_to));
    }

    try body.put("sort_field", data.string(sort_field_string));
    try body.put("sort_order", data.string(sort_order_string));

    const all_tags = try data.array();
    var all_tags_iterator = handler.all_tags.iterator();
    while (all_tags_iterator.next()) |tag| {
        try all_tags.append(data.string(tag.key_ptr.*));
    }

    try body.put("all_tags", all_tags);

    const all_assignments = try data.array();
    var all_assignments_iterator = handler.all_assignments.iterator();
    while (all_assignments_iterator.next()) |tag| {
        try all_assignments.append(data.string(tag.key_ptr.*));
    }

    try body.put("all_assignments", all_assignments);

    const tasks = try data.array();

    var filtered_tasks: std.ArrayListUnmanaged(DirWalker.FileTask) = try .initCapacity(req.arena, handler.files.len);
    defer filtered_tasks.deinit(req.arena);

    for (handler.files) |file_task| {
        if (!DirWalker.passesFilter(file_task.task, .{
            .maybe_query = if (filter_query.len > 0) filter_query else null,
            .tags = request_filter_tags.items,
            .filter_assignment = filter_assignment,
            .maybe_assigned_to = filter_assigned_to_string,
        })) continue;
        filtered_tasks.appendAssumeCapacity(file_task);
    }

    ls.sortWithContext(filtered_tasks.items, .{
        .sort = sort_field,
        .order = sort_order,
    });

    for (filtered_tasks.items) |file_task| {
        try tasks.append(try createTaskObject(&data, file_task));
    }

    try body.put("tasks", tasks);

    const output = try page_template.render(&data, void, {}, .{
        .layout = layout_template,
    });
    res.body = output;
}

fn getTaskShow(handler: Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const query_parameters = try req.query();
    const id = query_parameters.get("id") orelse {
        res.status = 404;
        res.body = "Unknown task";
        return;
    };

    const file_task = for (handler.files) |file_task| {
        if (std.mem.eql(u8, file_task.path, id)) break file_task;
    } else {
        res.status = 404;
        res.body = "Unknown task";
        return;
    };

    const layout_template = zmpl.find("layouts/main") orelse {
        res.status = 500;
        res.body = "Internal server error";
        return;
    };

    const page_template = zmpl.find("show") orelse {
        res.status = 500;
        res.body = "Internal server error";
        return;
    };

    res.status = 200;

    var data: zmpl.Data = .init(req.arena);

    const body = try data.object();
    try body.put("cached_at_timestamp", try createCachedAtString(req.arena, &data, handler.cached_at_timestamp));
    try body.put("task", try createTaskObject(&data, file_task));

    const output = try page_template.render(&data, void, {}, .{
        .layout = layout_template,
    });
    res.body = output;
}

fn getResources(handler: Handler, req: *httpz.Request, res: *httpz.Response) !void {
    _ = handler;

    const resources_paths = .{
        .{ "base_styles.css", @embedFile("../views/resources/base_styles.css") },
    };

    const requested_resource = req.url.path["/resources/".len..];

    inline for (resources_paths) |entry| {
        const url_path, const file_data = entry;
        if (std.mem.eql(u8, url_path, requested_resource)) {
            res.status = 200;
            res.body = file_data;
            return;
        }
    }

    res.status = 404;
}
