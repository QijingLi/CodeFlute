const std = @import("std");

pub const Config = struct {
    api_key: []const u8,
    api_base: []const u8,
    model: []const u8,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        allocator.free(self.api_key);
        allocator.free(self.api_base);
        allocator.free(self.model);
    }

    pub fn load(allocator: std.mem.Allocator) !Config {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return error.HomeDirNotFound;
        };
        defer allocator.free(home);

        const config_dir = try std.fs.path.join(allocator, &.{ home, ".codeflute" });
        defer allocator.free(config_dir);

        const config_path = try std.fs.path.join(allocator, &.{ config_dir, "config.json" });
        defer allocator.free(config_path);

        const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| {
            if (err == error.FileNotFound) return Config{
                .api_key = try allocator.dupe(u8, ""),
                .api_base = try allocator.dupe(u8, "https://generativelanguage.googleapis.com"),
                .model = try allocator.dupe(u8, "gemini-1.5-flash"),
            };
            return err;
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        const parsed = try std.json.parseFromSlice(Config, allocator, content, .{});
        defer parsed.deinit();

        return Config{
            .api_key = try allocator.dupe(u8, parsed.value.api_key),
            .api_base = try allocator.dupe(u8, parsed.value.api_base),
            .model = try allocator.dupe(u8, parsed.value.model),
        };
    }

    pub fn save(self: Config, allocator: std.mem.Allocator) !void {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return error.HomeDirNotFound;
        };
        defer allocator.free(home);

        const config_dir = try std.fs.path.join(allocator, &.{ home, ".codeflute" });
        defer allocator.free(config_dir);

        std.fs.makeDirAbsolute(config_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const config_path = try std.fs.path.join(allocator, &.{ config_dir, "config.json" });
        defer allocator.free(config_path);

        const file = try std.fs.createFileAbsolute(config_path, .{});
        defer file.close();

        var buf: [4096]u8 = undefined;
        var writer = file.writer(&buf);
        try std.json.Stringify.value(self, .{}, &writer.interface);
        try writer.interface.flush();
    }
};
