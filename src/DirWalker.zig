const std = @import("std");

const Task = @import("./Task.zig");

const DirWalker = @This();

pub const FileTask = struct {
    path: []const u8,
    task: Task,

    pub fn deinit(self: FileTask, allocator: std.mem.Allocator) void {
        self.task.deinit(allocator);
        allocator.free(self.path);
    }
};

pub const Filter = struct {
    maybe_query: ?[]const u8 = null,
    tags: []const []const u8 = &.{},
};

allocator: std.mem.Allocator,
collector: *std.ArrayListUnmanaged(FileTask),
name_buffer: std.ArrayListUnmanaged(u8) = .empty,
filter: Filter = .{},

pub fn init(allocator: std.mem.Allocator, collector: *std.ArrayListUnmanaged(FileTask)) DirWalker {
    return .{
        .allocator = allocator,
        .collector = collector,
    };
}

pub fn deinit(self: *DirWalker, allocator: std.mem.Allocator) void {
    self.name_buffer.deinit(allocator);
}

pub fn addFileWithPath(self: *DirWalker, file: std.fs.File, whole_path: []const u8) !void {
    const formatted_path = try self.allocator.dupe(u8, whole_path);
    errdefer self.allocator.free(formatted_path);

    const task = try Task.initFromFile(self.allocator, file);
    errdefer task.deinit(self.allocator);

    const passes_filter = filter_check: {
        if (self.filter.maybe_query) |query| {
            if (!std.mem.containsAtLeast(u8, task.name, 1, query)) break :filter_check false;
        }
        for (self.filter.tags) |tag| {
            const has_tag = for (task.tags) |task_tag| {
                if (std.mem.eql(u8, tag, task_tag)) break true;
            } else false;
            if (!has_tag) break :filter_check false;
        }
        break :filter_check true;
    };
    if (!passes_filter) {
        task.deinit(self.allocator);
        self.allocator.free(formatted_path);
        return;
    }

    try self.collector.append(self.allocator, .{
        .path = formatted_path,
        .task = task,
    });
}

pub fn walkDirectory(self: *DirWalker, dir: std.fs.Dir) !void {
    const start_pos = self.collector.items.len;
    errdefer self.name_buffer.shrinkRetainingCapacity(start_pos);
    errdefer for (self.collector.items[start_pos..]) |item| item.deinit(self.allocator);

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        const name_buffer_pos = self.name_buffer.items.len;
        defer self.name_buffer.shrinkRetainingCapacity(name_buffer_pos);
        try self.name_buffer.appendSlice(self.allocator, entry.name);
        switch (entry.kind) {
            .directory => {
                try self.name_buffer.append(self.allocator, std.fs.path.sep);
                var sub_directory = try dir.openDir(entry.name, .{ .iterate = true });
                defer sub_directory.close();
                try self.walkDirectory(sub_directory);
            },
            .file => {
                if (!std.mem.eql(u8, std.fs.path.extension(entry.name), ".ono")) continue;

                const file = try dir.openFile(entry.name, .{});
                defer file.close();
                try self.addFileWithPath(
                    file,
                    self.name_buffer.items,
                );
            },
            else => {},
        }
    }
}
