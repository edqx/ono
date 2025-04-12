const std = @import("std");

const OnoIgnore = @This();

ignore_list: [][]const u8,

pub fn parseOnoIgnoreAlloc(allocator: std.mem.Allocator, file_data: []const u8) !OnoIgnore {
    var ignore_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer ignore_list.deinit(allocator);
    defer for (ignore_list.items) |path| allocator.free(path);
    var tokenise = std.mem.tokenizeAny(u8, file_data, "\r\n");
    while (tokenise.next()) |line| {
        const start_pos = std.mem.indexOfNone(u8, line, std.ascii.whitespace) orelse continue;
        const end_pos = std.mem.lastIndexOfNone(u8, line, std.ascii.whitespace) orelse continue;
        const path = line[start_pos .. end_pos + 1];
        if (path[0] == '#') continue;
        const dupe = try allocator.dupe(u8, path);
        errdefer allocator.free(dupe);
        try ignore_list.append(allocator, dupe);
    }
    return .{
        .ignore_list = try ignore_list.toOwnedSlice(allocator),
    };
}

pub fn deinit(self: OnoIgnore, allocator: std.mem.Allocator) void {
    for (self.ignore_list) |pattern| allocator.free(pattern);
    allocator.free(self.ignore_list);
}

// algorithm from https://www.codeproject.com/Articles/5163931/Fast-String-Matching-with-Wildcards-Globs-and-Giti
// pub fn globMatches(pattern_const: []const u8, path_const: []const u8) bool {
//     var path1_backup: ?[]const u8 = null;
//     var pattern1_backup: ?[]const u8 = null;
//     var path2_backup: ?[]const u8 = null;
//     var pattern2_backup: ?[]const u8 = null;

//     var pattern = pattern_const;
//     var path = path_const;
//     if (pattern[0] == '/') {
//         while (path[0] == '.' and path[1] == std.fs.path.sep) {
//             path = path[2..];
//         }
//         if (path[0] == std.fs.path.sep) {
//             path = path[1..];
//         }
//         pattern = pattern[1..];
//     } else if (std.mem.indexOfScalar(u8, pattern, '/') == 0) {
//         if (std.mem.lastIndexOfScalar(u8, path, std.fs.path.sep)) |sep_pos| {
//             path = path[sep_pos + 1 ..];
//         }
//     }
//     while (path.len > 0) {
//         switch (pattern[0]) {
//             '*' => {
//                 pattern = pattern[1..];
//                 if (pattern[0] == '*') {
//                     pattern = pattern[1..];
//                     if (pattern.len == 0) return true;
//                     if (pattern[0] != '/') return false;
//                     path1_backup = null;
//                     pattern1_backup = null;
//                     path2_backup = path;
//                     pattern = pattern[1..];
//                     pattern2_backup = pattern;
//                     continue;
//                 }
//                 path1_backup = path;
//                 pattern1_backup = pattern;
//                 continue;
//             },
//             '?' => {
//                 if (path[0] == std.fs.path.sep) break;
//                 path = path[1..];
//                 pattern = pattern[1..];
//                 continue;
//             },
//             '[' => {
//                 const reverse = pattern[1] == '^' or pattern[1] == '!';
//                 if (path[0] == std.fs.path.sep) break;
//                 if (reverse) pattern = pattern[1..];
//                 for (var last)
//             }
//         }
//     }
// }

pub fn isPathIgnored(self: OnoIgnore, path: []const u8) bool {
    for (self.ignore_list) |ignore_pattern| {
        // var split_pattern = std.mem.splitAny(u8, ignore_pattern, "\\/");
        // var split_path = std.mem.splitAny(u8, path, "\\/");
        if (std.mem.eql(u8, ignore_pattern, path)) return true;
    }
    return false;
}
