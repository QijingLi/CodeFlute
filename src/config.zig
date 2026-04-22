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

    pub fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return error.HomeDirNotFound;
        };
        defer allocator.free(home);

        const config_dir = try std.fs.path.join(allocator, &.{ home, ".codeflute" });
        defer allocator.free(config_dir);

        return try std.fs.path.join(allocator, &.{ config_dir, "config.json" });
    }

    pub fn load(allocator: std.mem.Allocator) !Config {
        const config_path = try getConfigPath(allocator);
        defer allocator.free(config_path);
        return try loadFromPath(allocator, config_path);
    }

    pub fn loadFromPath(allocator: std.mem.Allocator, config_path: []const u8) !Config {
        const file = std.fs.openFileAbsolute(config_path, .{}) catch |err| {
            if (err == error.FileNotFound) return Config{
                .api_key = try allocator.dupe(u8, ""),
                .api_base = try allocator.dupe(u8, "https://generativelanguage.googleapis.com/v1"),
                .model = try allocator.dupe(u8, "models/gemini-2.0-flash"),
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
        const config_path = try getConfigPath(allocator);
        defer allocator.free(config_path);

        const config_dir = std.fs.path.dirname(config_path).?;
        std.fs.makeDirAbsolute(config_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        const file = try std.fs.createFileAbsolute(config_path, .{});
        defer file.close();

        var json_payload: std.ArrayList(u8) = .empty;
        defer json_payload.deinit(allocator);
        var list_writer = json_payload.writer(allocator);
        var adapter = list_writer.adaptToNewApi(&.{});
        try std.json.Stringify.value(self, .{}, &adapter.new_interface);
        try file.writeAll(json_payload.items);
    }
};

test "Config load and save" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const tmp_path = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    const config_path = try std.fs.path.join(allocator, &.{ tmp_path, "test_config.json" });
    defer allocator.free(config_path);

    var cfg = Config{
        .api_key = try allocator.dupe(u8, "test-key"),
        .api_base = try allocator.dupe(u8, "https://test.api"),
        .model = try allocator.dupe(u8, "test-model"),
    };
    defer cfg.deinit(allocator);

    // Save it manually to a file since we don't have saveToPath yet
    const file = try std.fs.createFileAbsolute(config_path, .{});
    defer file.close();
    var json_payload: std.ArrayList(u8) = .empty;
    defer json_payload.deinit(allocator);
    var list_writer = json_payload.writer(allocator);
    var adapter = list_writer.adaptToNewApi(&.{});
    try std.json.Stringify.value(cfg, .{}, &adapter.new_interface);
    try file.writeAll(json_payload.items);

    var loaded = try Config.loadFromPath(allocator, config_path);
    defer loaded.deinit(allocator);

    try std.testing.expectEqualStrings(cfg.api_key, loaded.api_key);
    try std.testing.expectEqualStrings(cfg.api_base, loaded.api_base);
    try std.testing.expectEqualStrings(cfg.model, loaded.model);
}

