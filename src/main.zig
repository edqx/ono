const std = @import("std");
const builtin = @import("builtin");

const createHelpScreenSection = @import("./help_screen.zig").createHelpScreenSection;

const help_screen = "ono <sub-command> [...options]\n\n" ++
    "Sub Commands:\n" ++
    createHelpScreenSection(.{
        .{ "ls", "list and search tasks" },
        .{ "init", "create a new task interactively" },
        .{ "resolve", "mark a task as resolved" },
        .{ "tag", "add tags to a task" },
        .{ "comment", "add a comment note to a task" },
        .{ "check", "validate tasks" },
        .{ "serve", "start a web server to view tasks, and rest api for managing them" },
    });

const commands_map = .{
    .{ "ls", @import("commands/ls.zig") },
    // .{ "new", @import("commands/new.zig") },
    // .{ "resolve", @import("commands/resolve.zig") },
    // .{ "tag", @import("commands/tag.zig") },
    // .{ "comment", @import("commands/comment.zig") },
    // .{ "check", @import("commands/check.zig") },
    // .{ "serve", @import("commands/serve.zig") },
};

const use_gpa = switch (builtin.mode) {
    .Debug, .ReleaseSafe => true,
    .ReleaseFast, .ReleaseSmall => false,
};

pub fn main() !void {
    const stdout_writer = std.io.getStdOut().writer();
    const stderr_writer = std.io.getStdErr().writer();

    var gpa = if (use_gpa) std.heap.GeneralPurposeAllocator(.{}){} else {};
    defer if (comptime use_gpa) std.debug.assert(gpa.deinit() == .ok);
    const allocator = if (comptime use_gpa) gpa.allocator() else std.heap.c_allocator;

    var args_iterator = try std.process.argsWithAllocator(allocator);
    defer args_iterator.deinit();

    const executable = args_iterator.next() orelse {
        try stdout_writer.print("{s}\n", .{help_screen});
        return error.UnknownSubCommand;
    };
    _ = executable;

    const sub_command = args_iterator.next() orelse {
        try stdout_writer.print("{s}\n", .{help_screen});
        return error.UnknownSubCommand;
    };

    const arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    inline for (commands_map) |entry| {
        const sub_command_name, const sub_command_namespace = entry;
        if (std.mem.eql(u8, sub_command, sub_command_name)) {
            try sub_command_namespace.exec(allocator, &args_iterator, stdout_writer, stderr_writer);
            break;
        }
    } else {
        try stdout_writer.print("{s}\n", .{help_screen});
        return error.UnknownSubCommand;
    }
}
