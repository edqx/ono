const std = @import("std");

const OnoIgnore = @import("../OnoIgnore.zig");
const Task = @import("../Task.zig");
const DirWalker = @import("../DirWalker.zig");

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

    pub fn fromShorthand(char: u8) ?Sort {
        return switch (char) {
            'n' => .name,
            else => null,
        };
    }
};

pub const Order = enum {
    ascending,
    descending,

    pub fn fromShorthand(char: u8) ?Order {
        return switch (char) {
            'a' => .ascending,
            'd' => .descending,
            else => null,
        };
    }
};

pub const SortContext = struct {
    sort: Sort,
    order: Order,
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
            input_sort = if (next_arg.len == 1)
                Sort.fromShorthand(next_arg[0]) orelse return Error.BadSort
            else
                std.meta.stringToEnum(Sort, next_arg) orelse return Error.BadSort;
            continue :process_flag .init;
        },
        .order => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            input_order = if (next_arg.len == 1)
                Order.fromShorthand(next_arg[0]) orelse return Error.BadOrder
            else
                std.meta.stringToEnum(Order, next_arg) orelse return Error.BadOrder;
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

    var file_tasks: std.ArrayListUnmanaged(DirWalker.FileTask) = .empty;
    defer file_tasks.deinit(allocator);
    defer for (file_tasks.items) |file_task| file_task.deinit(allocator);

    var dir_walker: DirWalker = .init(allocator, &file_tasks);
    defer dir_walker.deinit(allocator);

    dir_walker.filter = .{
        .maybe_query = input_query,
        .tags = input_tags.items,
    };

    for (input_paths.items) |path| {
        _ = std.fs.cwd().statFile(path) catch |e| switch (e) {
            error.IsDir => {
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

    std.mem.sort(DirWalker.FileTask, file_tasks.items, @as(SortContext, .{
        .sort = sort,
        .order = order,
    }), struct {
        fn nullLessThan(a: anytype, b: anytype) bool {
            if (a == null and b == null) return false;
            if (a == null and b != null) return true;
            if (a != null and b == null) return false;
            return a.? < b.?;
        }

        pub fn lessThanFn(ctx: SortContext, a: DirWalker.FileTask, b: DirWalker.FileTask) bool {
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

    for (file_tasks.items) |file_task| {
        if (hide_details) {
            try stdout_writer.print("{s}\n", .{file_task.path});
        } else {
            try stdout_writer.print("{s} - {s}\n", .{ file_task.path, file_task.task.name });
        }
    }
}
