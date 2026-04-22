const std = @import("std");

pub fn searchInFiles(allocator: std.mem.Allocator, dir: std.fs.Dir, pattern: []const u8) !void {
    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        // Skip common build/vcs directories
        if (std.mem.containsAtLeast(u8, entry.path, 1, "zig-cache") or
            std.mem.containsAtLeast(u8, entry.path, 1, "zig-out") or
            std.mem.containsAtLeast(u8, entry.path, 1, ".git"))
        {
            continue;
        }

        if (entry.kind != .file) continue;


        const file = try dir.openFile(entry.path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024 * 10); // 10MB limit
        defer allocator.free(content);

        if (std.mem.indexOf(u8, content, pattern)) |pos| {
            // Found a match
            var line_num: usize = 1;
            for (content[0..pos]) |c| {
                if (c == '\n') line_num += 1;
            }
            std.debug.print("{s}:{d}\n", .{ entry.path, line_num });
        }
    }
}

test "searchInFiles basic" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(.{ .sub_path = "test1.txt", .data = "hello world\nthis is a test\nzig is cool" });
    try tmp.dir.writeFile(.{ .sub_path = "test2.txt", .data = "another file\nwith zig code" });

    // Since searchInFiles prints to debug, we can't easily capture it,
    // but we can at least ensure it doesn't crash.
    try searchInFiles(allocator, tmp.dir, "zig");
}

