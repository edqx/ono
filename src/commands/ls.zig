const std = @import("std");

const OnoIgnore = @import("../OnoIgnore.zig");
const Task = @import("../Task.zig");

const createHelpScreenSection = @import("../help_screen.zig").createHelpScreenSection;

const help_screen = "ono list [...paths] [-hrqtHso]\n\n" ++
    "Parameters:\n" ++
    createHelpScreenSection(.{
        .{ "paths", "the folders and files to list tasks from, default is current working directory" },
    }) ++ "\n\n" ++
    "Options:\n" ++
    createHelpScreenSection(.{
        .{ "-h, --help", "show this screen" },
        .{ "-r, --recursive", "search all sub-directories recursively" },
        .{ "-q, --query <query>", "full-text search of all text-based fields in the tasks" },
        .{ "-t, --tag <tag>", "search for tasks with a particular tag" },
        .{ "-H, --hide-details", "whether to hide details of a task, only printing the file path" },
        .{ "-s, --sort <\"name\">", "sort by name alphabetically" },
        .{ "-o, --order <\"ascending\"|\"descending\">", "use with --sort to determine whether the listing should be ascending or descending" },
    });

pub const Error = error{ MissingArgument, UnknownFlag, BadSort, BadOrder };

pub const Flag = enum {
    init,
    help,
    recursive,
    query,
    tag,
    @"hide-details",
    sort,
    order,

    pub fn fromShorthand(char: u8) ?Flag {
        return switch (char) {
            'h' => .help,
            'r' => .recursive,
            'q' => .query,
            't' => .tag,
            'H' => .@"hide-details",
            's' => .sort,
            'o' => .order,
            else => null,
        };
    }
};

pub const Sort = enum {
    // created,
    // modified,
    name,
};

pub const Order = enum {
    ascending,
    descending,
};

pub const SortContext = struct {
    sort: Sort,
    order: Order,
};

pub const FileTask = struct {
    path: []const u8,
    task: Task,

    pub fn deinit(self: FileTask, allocator: std.mem.Allocator) void {
        self.task.deinit(allocator);
        allocator.free(self.path);
    }
};

pub fn exec(allocator: std.mem.Allocator, args_iterator: *std.process.ArgIterator, stdout_writer: anytype, stderr_writer: anytype) !void {
    _ = stderr_writer;

    var input_paths: std.ArrayListUnmanaged([]const u8) = .empty;
    defer input_paths.deinit(allocator);
    defer for (input_paths.items) |path| allocator.free(path);
    var input_show_help: bool = false;
    var input_recursive: bool = false;
    var input_query: ?[]const u8 = null;
    defer if (input_query) |query| allocator.free(query);
    var input_tags: std.ArrayListUnmanaged([]const u8) = .empty;
    defer input_tags.deinit(allocator);
    defer for (input_tags.items) |tag| allocator.free(tag);
    var hide_details: bool = false;
    var input_sort: ?Sort = null;
    var input_order: ?Order = null;

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
        .query => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            input_query = try allocator.dupe(u8, next_arg);
            continue :process_flag .init;
        },
        .tag => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            const duped_tag = try allocator.dupe(u8, next_arg);
            errdefer allocator.free(duped_tag);
            try input_tags.append(allocator, duped_tag);
            continue :process_flag .init;
        },
        .@"hide-details" => {
            hide_details = true;
            continue :process_flag .init;
        },
        .sort => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            input_sort = std.meta.stringToEnum(Sort, next_arg) orelse return Error.BadSort;
            continue :process_flag .init;
        },
        .order => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            input_order = std.meta.stringToEnum(Order, next_arg) orelse return Error.BadOrder;
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

    const sort: Sort = input_sort orelse .name;
    const order: Order = input_order orelse switch (sort) {
        // .created => .descending,
        // .modified => .descending,
        .name => .ascending,
    };

    var file_tasks: std.ArrayListUnmanaged(FileTask) = .empty;
    defer file_tasks.deinit(allocator);
    defer for (file_tasks.items) |file_task| file_task.deinit(allocator);

    for (input_paths.items) |path| {
        _ = std.fs.cwd().statFile(path) catch |e| switch (e) {
            error.IsDir => {
                var root_directory = try std.fs.cwd().openDir(path, .{ .iterate = true });
                defer root_directory.close();

                var walker = try root_directory.walk(allocator);
                defer walker.deinit();

                // var global_ono_ignore: OnoIgnore = .{ .ignore_list = &.{} };

                while (try walker.next()) |walk_entry| {
                    // if (global_ono_ignore.isPathIgnored(walk_entry.path)) {
                    //     _ = walker.stack.pop();
                    //     continue;
                    // }

                    switch (walk_entry.kind) {
                        .directory => {
                            if (!input_recursive) {
                                _ = walker.stack.pop();
                                continue;
                            }
                            // const sub_ono_ignore = walk_entry.dir.openFile("ono_ignore", .{}) catch |e| switch (e) {
                            //     error.FileNotFound => continue,
                            //     else => return e,
                            // };

                            // const ignore_data = try sub_ono_ignore.readToEndAlloc(allocator, std.math.maxInt(usize));
                            // defer allocator.free(ignore_data);

                            // const ono_ignore = try OnoIgnore.parseOnoIgnoreAlloc(allocator, ignore_data);
                            // defer ono_ignore.deinit(allocator);
                        },
                        .file => {
                            if (!std.mem.eql(u8, std.fs.path.extension(walk_entry.path), ".ono")) continue;

                            var file = try root_directory.openFile(walk_entry.path, .{});
                            defer file.close();

                            const task: Task = try Task.initFromFile(allocator, file);
                            errdefer task.deinit(allocator);
                            const duped_path = try std.fs.path.join(allocator, &.{ path, walk_entry.path });
                            errdefer allocator.free(duped_path);
                            try file_tasks.append(allocator, .{
                                .task = task,
                                .path = duped_path,
                            });
                        },
                        else => {},
                    }
                }
                continue;
            },
            else => return e,
        };

        if (!std.mem.eql(u8, std.fs.path.extension(path), ".ono")) continue;
        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const task: Task = try Task.initFromFile(allocator, file);
        errdefer task.deinit(allocator);
        const duped_path = try allocator.dupe(u8, path);
        errdefer allocator.free(duped_path);
        try file_tasks.append(allocator, .{
            .task = task,
            .path = duped_path,
        });
    }

    std.mem.sort(FileTask, file_tasks.items, @as(SortContext, .{
        .sort = sort,
        .order = order,
    }), struct {
        fn nullLessThan(a: anytype, b: anytype) bool {
            if (a == null and b == null) return false;
            if (a == null and b != null) return true;
            if (a != null and b == null) return false;
            return a.? < b.?;
        }

        pub fn lessThanFn(ctx: SortContext, a: FileTask, b: FileTask) bool {
            const is_less_than = switch (ctx.sort) {
                // .created => nullLessThan(a.created_at_ms, b.created_at_ms),
                // .modified => nullLessThan(a.modified_at_ms, b.modified_at_ms),
                .name => std.mem.order(u8, a.task.name, b.task.name) == .lt,
            };
            return switch (ctx.order) {
                .ascending => is_less_than,
                .descending => !is_less_than,
            };
        }
    }.lessThanFn);

    each_task: for (file_tasks.items) |file_task| {
        for (input_tags.items) |needle_tag| {
            const has_tag = for (file_task.task.tags) |haystack_tag| {
                if (std.mem.eql(u8, needle_tag, haystack_tag)) break true;
            } else false;
            if (!has_tag) continue :each_task;
        }

        if (input_query) |query| {
            if (std.mem.indexOf(u8, file_task.task.name, query) == null) {
                continue;
            }
        }

        if (hide_details) {
            try stdout_writer.print("{s}\n", .{file_task.path});
        } else {
            try stdout_writer.print("{s} - {s}\n", .{ file_task.path, file_task.task.name });
        }
    }
}
