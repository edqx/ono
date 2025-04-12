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

pub const Error = error{UnknownFlag};

pub const Flag = enum {
    init,
    help,

    pub fn fromShorthand(char: u8) ?Flag {
        return switch (char) {
            'h' => .help,
            else => null,
        };
    }
};

pub const commands = struct {
    pub const ls = @import("commands/ls.zig");
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

    var input_sub_command: ?[]const u8 = null;
    defer if (input_sub_command) |sub_command| allocator.free(sub_command);
    var input_show_help = false;

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
            input_sub_command = duped;
        },
        .help => {
            input_show_help = true;
            continue :process_flag .init;
        },
    }

    if (input_show_help) {
        try stdout_writer.print("{s}\n", .{help_screen});
        return;
    }

    const arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const sub_command = input_sub_command orelse {
        try stdout_writer.print("{s}\n", .{help_screen});
        return error.UnknownSubCommand;
    };

    inline for (@typeInfo(commands).@"struct".decls) |decl| {
        if (std.mem.eql(u8, decl.name, sub_command)) {
            try @field(commands, decl.name).exec(allocator, &args_iterator, stdout_writer, stderr_writer);
            break;
        }
    }
}
