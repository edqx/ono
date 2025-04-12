const std = @import("std");
const toml = @import("toml");

const Task = @This();

pub const Error = error{ BadName, BadTags, BadAttribution, BadAssignment, BadPriority, BadStatus, BadAttachments, BadDescription, BadNotes };

fn freeSliceElements(allocator: std.mem.Allocator, list: anytype) void {
    for (list) |elem| allocator.free(elem);
}

fn stringValue(allocator: std.mem.Allocator, value: toml.Value) !?[]const u8 {
    if (value != .string or value.string.len == 0) return null;
    return try allocator.dupe(u8, value.string);
}

fn arrayOfStringsValue(allocator: std.mem.Allocator, value: toml.Value) !?[][]const u8 {
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

    pub fn initFromTable(allocator: std.mem.Allocator, table: toml.Table) !Note {
        var out: Note = undefined;

        const attributed_to_value = table.get("attributed_to");
        out.maybe_attributed_to = if (attributed_to_value) |value| try stringValue(allocator, value) orelse return Error.BadNotes else null;
        errdefer if (out.maybe_attributed_to) |attributed_to| allocator.free(attributed_to);

        const note_value = table.get("note");
        out.maybe_note = if (note_value) |value| try stringValue(allocator, value) orelse return Error.BadNotes else null;
        errdefer if (out.maybe_attributed_to) |attributed_to| allocator.free(attributed_to);

        const attachments_value = table.get("tags");
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
};

name: []const u8,
tags: [][]const u8,
maybe_assigned_to: ?[]const u8,
maybe_priority: ?[]const u8,
maybe_status: ?[]const u8,

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

    var parser: toml.Parser(toml.Table) = .init(allocator);
    defer parser.deinit();

    const parsed = try parser.parseString(file_data);
    defer parsed.deinit();

    const task = try initFromTable(allocator, parsed.value);
    errdefer task.deinit(allocator);

    // return .{
    //     .task = task,
    //     .created_at_ms = created_at_ms,
    //     .modified_at_ms = modified_at_ms,
    // };
    return task;
}

pub fn initFromTable(allocator: std.mem.Allocator, table: toml.Table) !Task {
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
    out.maybe_priority = if (priority_value) |value| try stringValue(allocator, value) orelse return Error.BadPriority else null;
    errdefer if (out.maybe_priority) |priority| allocator.free(priority);

    const status_value = table.get("status");
    out.maybe_status = if (status_value) |value| try stringValue(allocator, value) orelse return Error.BadStatus else null;
    errdefer if (out.maybe_status) |status| allocator.free(status);

    const notes_value = table.get("notes") orelse return Error.BadNotes;
    if (notes_value != .array) return Error.BadNotes;
    var notes_list: std.ArrayListUnmanaged(Note) = try .initCapacity(allocator, notes_value.array.items.len);
    defer notes_list.deinit(allocator);
    defer for (notes_list.items) |note| note.deinit(allocator);
    for (notes_value.array.items) |note_value| {
        if (note_value != .table) return Error.BadNotes;
        const note: Note = try .initFromTable(allocator, note_value.table.*);
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
    if (self.maybe_status) |status| allocator.free(status);
    if (self.maybe_priority) |priority| allocator.free(priority);
    if (self.maybe_assigned_to) |assigned_to| allocator.free(assigned_to);
    for (self.tags) |tag| allocator.free(tag);
    allocator.free(self.tags);
    allocator.free(self.name);
}
