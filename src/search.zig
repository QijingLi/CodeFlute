const std = @import("std");

pub fn searchInFiles(allocator: std.mem.Allocator, pattern: []const u8) !void {
    const cwd = std.fs.cwd();
    var dir = try cwd.openDir(".", .{ .iterate = true });
    defer dir.close();

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
