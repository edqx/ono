const std = @import("std");
const zmpl = @import("zmpl");
const httpz = @import("httpz");

const OnoIgnore = @import("../OnoIgnore.zig");
const Task = @import("../Task.zig");
const DirWalker = @import("../DirWalker.zig");

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

    const cached_at_timestamp = std.time.milliTimestamp();

    var server: httpz.Server(Handler) = try .init(allocator, .{
        .address = "0.0.0.0",
        .port = 57800,
    }, .{
        .cached_at_timestamp = cached_at_timestamp,
        .files = dir_walker.collector.items,
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

fn getHomePage(handler: Handler, req: *httpz.Request, res: *httpz.Response) !void {
    const page_template = zmpl.find("home") orelse {
        res.status = 500;
        res.body = "Internal server error";
        return;
    };

    res.status = 200;

    var data: zmpl.Data = .init(req.arena);

    const body = try data.object();

    const tasks = try data.array();

    for (handler.files) |file_task| {
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

        try tasks.append(obj);
    }

    try body.put("tasks", tasks);

    const output = try page_template.render(&data, void, {}, .{});
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
        if (std.mem.eql(u8, file_task.path, id)) break file_task.task;
    } else {
        res.status = 404;
        res.body = "Unknown task";
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
    try body.put("name", data.string(file_task.name));

    const output = try page_template.render(&data, void, {}, .{});
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
