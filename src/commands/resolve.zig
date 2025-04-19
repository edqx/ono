const std = @import("std");
const microwave = @import("microwave");

const OnoIgnore = @import("../OnoIgnore.zig");
const Task = @import("../Task.zig");
const DirWalker = @import("../DirWalker.zig");

const createHelpScreenSection = @import("../help_screen.zig").createHelpScreenSection;

const help_screen = "ono resolve <file> [...additional files] [-s]\n\n" ++
    "Parameters:\n" ++
    createHelpScreenSection(.{
        .{ "file", "file of the task to update the status for" },
        .{ "additional files", "more files of tasks to update the status for" },
    }) ++ "\n\n" ++
    "Options:\n" ++
    createHelpScreenSection(.{
        .{ "-h, --help", "show this screen" },
        .{ "-s, --status <status>", "the status to mark the task as, one of 'none', 'unresolved', 'resolved', default is resolved" },
    });

pub const Error = error{ MissingArgument, UnknownFlag, NoTasksToResolve, BadStatus };

pub const Flag = enum {
    init,
    help,
    status,

    pub fn fromShorthand(char: u8) ?Flag {
        return switch (char) {
            'h' => .help,
            's' => .status,
            else => null,
        };
    }
};

pub fn exec(allocator: std.mem.Allocator, args_iterator: *std.process.ArgIterator, stdout_writer: anytype, stderr_writer: anytype) !void {
    var input_show_help: bool = false;

    var input_paths: std.ArrayListUnmanaged([]const u8) = .empty;
    defer input_paths.deinit(allocator);
    defer for (input_paths.items) |path| allocator.free(path);

    var input_status: Task.Status = .resolved;

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
        .status => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            input_status = std.meta.stringToEnum(Task.Status, next_arg) orelse return Error.BadStatus;
            continue :process_flag .init;
        },
    }

    if (input_show_help) {
        try stdout_writer.print("{s}\n", .{help_screen});
        return;
    }

    if (input_paths.items.len == 0) {
        try stderr_writer.print("{s}\n", .{help_screen});
        return Error.NoTasksToResolve;
    }

    for (input_paths.items) |path| {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
        defer file.close();

        var task = try Task.initFromFile(allocator, file);
        defer task.deinit(allocator);

        task.status = input_status;

        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();

        const table = try task.toTableAlloc(arena.allocator());

        try file.seekTo(0);
        try file.setEndPos(0);

        try microwave.stringify.writeTable(arena.allocator(), table, file.writer());
    }
}
