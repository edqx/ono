const std = @import("std");
const microwave = @import("microwave");

const OnoIgnore = @import("../OnoIgnore.zig");
const Task = @import("../Task.zig");
const DirWalker = @import("../DirWalker.zig");

const createHelpScreenSection = @import("../help_screen.zig").createHelpScreenSection;

const help_screen = "ono tag <file> [...additional files] [-hsuo]\n\n" ++
    "Parameters:\n" ++
    createHelpScreenSection(.{
        .{ "file", "file of the task to modify the tags for" },
        .{ "additional files", "more files of tasks to modify the tags for" },
    }) ++ "\n\n" ++
    "Options:\n" ++
    createHelpScreenSection(.{
        .{ "-h, --help", "show this screen" },
        .{ "-s, --set <tag>", "add a tag to the tasks, unless it is already added" },
        .{ "-u, --unset <tag>", "remove a tag from the tasks, unless it is not added" },
        .{ "-o, --overwrite <tag>", "overwrite the existing tags in the tasks, --set, --unset and --clear must not be used" },
        .{ "-c, --clear", "remove all tags in the task, --set, --unset, and --overwrite must not be used" },
    });

pub const Error = error{ MissingArgument, UnknownFlag, NoTasksToTag, BadOverwrite, BadClear };

pub const Flag = enum {
    init,
    help,
    set,
    unset,
    overwrite,
    clear,

    pub fn fromShorthand(char: u8) ?Flag {
        return switch (char) {
            'h' => .help,
            's' => .set,
            'u' => .unset,
            'o' => .overwrite,
            'c' => .clear,
            else => null,
        };
    }
};

pub fn exec(allocator: std.mem.Allocator, args_iterator: *std.process.ArgIterator, stdout_writer: anytype, stderr_writer: anytype) !void {
    var input_show_help: bool = false;

    var input_paths: std.ArrayListUnmanaged([]const u8) = .empty;
    defer input_paths.deinit(allocator);
    defer for (input_paths.items) |path| allocator.free(path);

    var input_set: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer input_set.deinit(allocator);

    var input_unset: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer input_unset.deinit(allocator);

    var input_overwrite: std.StringArrayHashMapUnmanaged(void) = .empty;
    defer input_overwrite.deinit(allocator);

    var input_clear: bool = false;

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
        .set => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            try input_set.put(allocator, next_arg, {});
            continue :process_flag .init;
        },
        .unset => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            try input_unset.put(allocator, next_arg, {});
            continue :process_flag .init;
        },
        .overwrite => {
            const next_arg = args_iterator.next() orelse return Error.MissingArgument;
            try input_overwrite.put(allocator, next_arg, {});
            continue :process_flag .init;
        },
        .clear => {
            input_clear = true;
            continue :process_flag .init;
        },
    }

    if (input_show_help) {
        try stdout_writer.print("{s}\n", .{help_screen});
        return;
    }

    if (input_overwrite.count() > 0 and (input_set.count() > 0 or input_unset.count() > 0 or input_clear)) {
        try stderr_writer.print("fatal: --unset, --set and --clear cannot be set when using --overwrite", .{});
        return Error.BadOverwrite;
    }

    if (input_clear and (input_set.count() > 0 or input_unset.count() > 0)) {
        try stderr_writer.print("fatal: --unset, --set and --overwrite cannot be set when using --clear", .{});
        return Error.BadClear;
    }

    const overwrite: ?[]const []const u8 = if (input_clear) &.{} else if (input_overwrite.count() > 0) input_overwrite.keys() else null;

    if (input_paths.items.len == 0) {
        try stdout_writer.print("{s}\n", .{help_screen});
        return Error.NoTasksToTag;
    }

    for (input_paths.items) |path| {
        const file = try std.fs.cwd().openFile(path, .{ .mode = .read_write });
        defer file.close();

        var task = try Task.initFromFile(allocator, file);
        defer task.deinit(allocator);

        const old_tags = task.tags;

        // don't take input_unset.count() since the tags might not exist
        var replace_tags: std.ArrayListUnmanaged([]const u8) = try .initCapacity(allocator, task.tags.len + input_overwrite.count() + input_set.count());

        errdefer replace_tags.deinit(allocator);
        errdefer for (replace_tags.items) |tag| allocator.free(tag);

        for (task.tags) |tag| {
            const duped = try allocator.dupe(u8, tag);
            errdefer allocator.free(duped);

            replace_tags.appendAssumeCapacity(duped);
            errdefer _ = replace_tags.pop();
        }

        if (overwrite) |new_tags| {
            for (replace_tags.items) |tag| allocator.free(tag);
            replace_tags.clearRetainingCapacity();

            for (new_tags) |new_tag| {
                const duped = try allocator.dupe(u8, new_tag);
                errdefer allocator.free(duped);

                replace_tags.appendAssumeCapacity(duped);
                errdefer _ = replace_tags.pop();
            }
        } else {
            for (input_set.keys()) |new_tag| {
                const key_exists = for (replace_tags.items) |tag| {
                    if (std.mem.eql(u8, tag, new_tag)) break true;
                } else false;

                if (key_exists) continue;

                const duped = try allocator.dupe(u8, new_tag);
                errdefer allocator.free(duped);

                replace_tags.appendAssumeCapacity(duped);
                errdefer _ = replace_tags.pop();
            }

            for (input_unset.keys()) |old_tag| {
                for (0.., replace_tags.items) |i, tag| {
                    if (std.mem.eql(u8, tag, old_tag)) {
                        allocator.free(replace_tags.swapRemove(i));
                        break;
                    }
                }
            }
        }

        task.tags = try replace_tags.toOwnedSlice(allocator);
        for (old_tags) |tag| allocator.free(tag);
        allocator.free(old_tags);

        var arena: std.heap.ArenaAllocator = .init(allocator);
        defer arena.deinit();

        const table = try task.toTableAlloc(arena.allocator());

        try file.seekTo(0);
        try file.setEndPos(0);

        try microwave.stringify.writeTable(arena.allocator(), table, file.writer());
        // var writer = file.writer().any();
        // try toml.serialize(arena.allocator(), table, &writer);
    }
}
