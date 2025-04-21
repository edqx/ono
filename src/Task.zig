const std = @import("std");
const microwave = @import("microwave");

const Task = @This();

pub const Error = error{ BadName, BadTags, BadAttribution, BadAssignment, BadPriority, BadStatus, BadAttachments, BadDescription, BadNotes };

fn freeSliceElements(allocator: std.mem.Allocator, list: anytype) void {
    for (list) |elem| allocator.free(elem);
}

fn stringValue(allocator: std.mem.Allocator, value: microwave.parse.Value) !?[]const u8 {
    if (value != .string or value.string.len == 0) return null;
    return try allocator.dupe(u8, value.string);
}

fn arrayOfStringsValue(allocator: std.mem.Allocator, value: microwave.parse.Value) !?[][]const u8 {
    if (value != .array) return null;
    var list: std.ArrayListUnmanaged([]const u8) = try .initCapacity(allocator, value.array.items.len);
    defer list.deinit(allocator);
    defer freeSliceElements(allocator, list.items);
    for (value.array.items) |value2| {
        if (value2 != .string) return null;
        const duped = try allocator.dupe(u8, value2.string);
        errdefer allocator.free(duped);
        list.appendAssumeCapacity(duped);
    }
    return try list.toOwnedSlice(allocator);
}

pub const Note = struct {
    maybe_attributed_to: ?[]const u8,
    maybe_note: ?[]const u8,
    attachments: [][]const u8,

    pub fn initFromTable(allocator: std.mem.Allocator, table: microwave.parse.Value.Table) !Note {
        var out: Note = undefined;

        const attributed_to_value = table.get("attributed_to");
        out.maybe_attributed_to = if (attributed_to_value) |value| try stringValue(allocator, value) orelse return Error.BadNotes else null;
        errdefer if (out.maybe_attributed_to) |attributed_to| allocator.free(attributed_to);

        const note_value = table.get("note");
        out.maybe_note = if (note_value) |value| try stringValue(allocator, value) orelse return Error.BadNotes else null;
        errdefer if (out.maybe_attributed_to) |attributed_to| allocator.free(attributed_to);

        const attachments_value = table.get("attachments");
        out.attachments = if (attachments_value) |value| try arrayOfStringsValue(allocator, value) orelse return Error.BadAttachments else &.{};
        errdefer allocator.free(out.attachments);
        errdefer freeSliceElements(allocator, out.attachments);

        return out;
    }

    pub fn deinit(self: Note, allocator: std.mem.Allocator) void {
        for (self.attachments) |attachment| allocator.free(attachment);
        allocator.free(self.attachments);
        if (self.maybe_note) |note| allocator.free(note);
        if (self.maybe_attributed_to) |attributed_to| allocator.free(attributed_to);
    }

    pub fn toTableAlloc(self: Note, arena: std.mem.Allocator) !microwave.parse.Value.Table {
        var table: microwave.parse.Value.Table = .empty;
        errdefer microwave.parse.deinitTable(arena, &table);

        if (self.maybe_attributed_to) |attributed_to| try table.put(arena, "attributed_to", .{ .string = try arena.dupe(u8, attributed_to) });
        if (self.maybe_note) |note| try table.put(arena, "note", .{ .string = try arena.dupe(u8, note) });

        if (self.attachments.len > 0) {
            var attachments: microwave.parse.Value.Array = try .initCapacity(arena, self.attachments.len);
            for (self.attachments) |attachment| attachments.appendAssumeCapacity(.{ .string = try arena.dupe(u8, attachment) });
            try table.put(arena, "attachments", .{ .array = attachments });
        }

        return table;
    }

    pub fn write(self: Note, write_stream: anytype) !void {
        if (self.maybe_attributed_to) |attributed_to| {
            try write_stream.beginKeyPair("attributed_to");
            try write_stream.writeString(attributed_to);
        }

        if (self.maybe_note) |note| {
            try write_stream.beginKeyPair("note");
            try write_stream.writeMultilineString(note);
        }

        if (self.attachments.len > 0) {
            try write_stream.beginKeyPair("attachments");
            try write_stream.beginArray();
            {
                for (self.attachments) |attachment| try write_stream.writeString(attachment);
            }
            try write_stream.endArray();
        }
    }
};

pub const Priority = enum {
    none,
    low,
    medium,
    high,
    critical,
};

pub const Status = enum {
    none,
    unresolved,
    resolved,
};

name: []const u8,
tags: [][]const u8,
maybe_assigned_to: ?[]const u8,
priority: Priority,
status: Status,

notes: []Note,

// pub const Timestamped = struct {
//     task: Task,
//     created_at_ms: ?i64,
//     modified_at_ms: ?i64,
// };

pub fn initFromFile(allocator: std.mem.Allocator, file: std.fs.File) !Task {
    // const metadata = try file.metadata();

    // const created_at_ms: ?i64 = if (metadata.created()) |created_at_nano| @intCast(@divFloor(created_at_nano, 1000 * 1000)) else null;
    // const modified_at_ms: ?i64 = @intCast(@divFloor(metadata.modified(), 1000 * 1000));

    const file_data = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(file_data);

    // return .{
    //     .task = task,
    //     .created_at_ms = created_at_ms,
    //     .modified_at_ms = modified_at_ms,
    // };
    return try initFromFileData(allocator, file_data);
}

pub fn initFromFileData(allocator: std.mem.Allocator, file_data: []const u8) !Task {
    const document = try microwave.parse.fromSlice(allocator, file_data);
    defer document.deinit();

    const task = try initFromTable(allocator, document.root_table);
    errdefer task.deinit(allocator);

    return task;
}

pub fn initFromTable(allocator: std.mem.Allocator, table: microwave.parse.Value.Table) !Task {
    var out: Task = undefined;

    out.name = try stringValue(allocator, table.get("name") orelse return Error.BadName) orelse return Error.BadName;

    const tags_value = table.get("tags");
    out.tags = if (tags_value) |value| try arrayOfStringsValue(allocator, value) orelse return Error.BadTags else &.{};
    errdefer allocator.free(out.tags);
    errdefer freeSliceElements(allocator, out.tags);

    const assigned_to_value = table.get("assigned_to");
    out.maybe_assigned_to = if (assigned_to_value) |value| try stringValue(allocator, value) orelse return Error.BadAssignment else null;
    errdefer if (out.maybe_assigned_to) |assigned_to| allocator.free(assigned_to);

    const priority_value = table.get("priority");
    out.priority = if (priority_value) |value| priority: {
        if (value != .string) return Error.BadPriority;
        break :priority std.meta.stringToEnum(Priority, value.string) orelse return Error.BadPriority;
    } else .none;

    const status_value = table.get("status");
    out.status = if (status_value) |value| priority: {
        if (value != .string) return Error.BadPriority;
        break :priority std.meta.stringToEnum(Status, value.string) orelse return Error.BadStatus;
    } else .none;

    const notes_value = table.get("notes") orelse return Error.BadNotes;
    if (notes_value != .array_of_tables) return Error.BadNotes;
    var notes_list: std.ArrayListUnmanaged(Note) = try .initCapacity(allocator, notes_value.array_of_tables.items.len);
    defer notes_list.deinit(allocator);
    defer for (notes_list.items) |note| note.deinit(allocator);
    for (notes_value.array_of_tables.items) |note_value| {
        const note: Note = try .initFromTable(allocator, note_value);
        errdefer note.deinit(allocator);
        notes_list.appendAssumeCapacity(note);
    }
    out.notes = try notes_list.toOwnedSlice(allocator);
    errdefer allocator.free(out.notes);
    errdefer for (out.notes) |note| note.deinit(allocator);

    return out;
}

pub fn deinit(self: Task, allocator: std.mem.Allocator) void {
    for (self.notes) |note| note.deinit(allocator);
    allocator.free(self.notes);
    if (self.maybe_assigned_to) |assigned_to| allocator.free(assigned_to);
    for (self.tags) |tag| allocator.free(tag);
    allocator.free(self.tags);
    allocator.free(self.name);
}

pub fn toTableAlloc(self: Task, arena: std.mem.Allocator) !microwave.parse.Value.Table {
    var table: microwave.parse.Value.Table = .empty;
    errdefer microwave.parse.deinitTable(arena, &table);

    try table.put(arena, "name", .{ .string = try arena.dupe(u8, self.name) });
    var tags: microwave.parse.Value.Array = try .initCapacity(arena, self.tags.len);
    for (self.tags) |tag| tags.appendAssumeCapacity(.{ .string = try arena.dupe(u8, tag) });
    try table.put(arena, "tags", .{ .array = tags });

    if (self.maybe_assigned_to) |assigned_to| try table.put(arena, "assigned_to", .{ .string = try arena.dupe(u8, assigned_to) });
    if (self.priority != .none) try table.put(arena, "priority", .{ .string = @tagName(self.priority) });
    if (self.status != .none) try table.put(arena, "status", .{ .string = @tagName(self.status) });

    var notes: microwave.parse.Value.ArrayOfTables = try .initCapacity(arena, self.notes.len);
    for (self.notes) |note| {
        const note_table = try note.toTableAlloc(arena);
        notes.appendAssumeCapacity(note_table);
    }
    try table.put(arena, "notes", .{ .array_of_tables = notes });

    return table;
}

pub fn write(self: Task, allocator: std.mem.Allocator, writer: anytype) !void {
    var write_stream: microwave.write_stream.Stream(@TypeOf(writer), .{}) = .{
        .underlying_writer = writer,
        .allocator = allocator,
    };
    defer write_stream.deinit();

    try write_stream.beginKeyPair("name");
    try write_stream.writeString(self.name);

    try write_stream.beginKeyPair("tags");
    try write_stream.beginArray();
    {
        for (self.tags) |tag| try write_stream.writeString(tag);
    }
    try write_stream.endArray();

    try writer.print("\n", .{});

    if (self.maybe_assigned_to) |assigned_to| {
        try write_stream.beginKeyPair("assigned_to");
        try write_stream.writeString(assigned_to);
    }

    if (self.priority != .none) {
        try write_stream.beginKeyPair("priority");
        try write_stream.writeString(@tagName(self.priority));
    }

    if (self.status != .none) {
        try write_stream.beginKeyPair("status");
        try write_stream.writeString(@tagName(self.status));
    }

    for (self.notes) |note| {
        try write_stream.writeManyTable("notes");
        try note.write(&write_stream);
    }
}
