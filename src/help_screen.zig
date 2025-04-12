const std = @import("std");

pub fn maxKeyLength(map: anytype) usize {
    var max_size = 0;
    inline for (map) |entry| {
        const key, _ = entry;
        if (key.len > max_size) max_size = key.len;
    }
    return max_size;
}

pub fn createHelpScreenSection(map: anytype) []const u8 {
    const indent = "  ";
    const max_key_length = indent.len + maxKeyLength(map);
    const max_tab = @divFloor(max_key_length, 8) + 1;
    var result: []const u8 = "";
    inline for (map) |entry| {
        const key, const val = entry;
        const next_tab = @divFloor(indent.len + key.len, 8);
        result = result ++ "\n" ++ indent ++ key ++ "\t" ** (max_tab - next_tab) ++ val;
    }
    return result;
}
