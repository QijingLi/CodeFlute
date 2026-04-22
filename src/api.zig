const std = @import("std");
const config = @import("config.zig");

pub fn callLLM(allocator: std.mem.Allocator, cfg: config.Config, prompt: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const endpoint = try std.fmt.allocPrint(allocator, "{s}/{s}:generateContent?key={s}", .{ cfg.api_base, cfg.model, cfg.api_key });
    defer allocator.free(endpoint);
    const uri = try std.Uri.parse(endpoint);

    const Part = struct { text: []const u8 };
    const Content = struct { parts: []const Part };
    const Payload = struct { contents: []const Content };
    const payload = Payload{
        .contents = &[_]Content{
            .{ .parts = &[_]Part{.{ .text = prompt }} },
        },
    };

    var json_payload: std.ArrayList(u8) = .empty;
    defer json_payload.deinit(allocator);
    var list_writer = json_payload.writer(allocator);
    var adapter = list_writer.adaptToNewApi(&.{});
    try std.json.Stringify.value(payload, .{}, &adapter.new_interface);

    var req = try client.request(.POST, uri, .{
        .extra_headers = &.{
            .{ .name = "Content-Type", .value = "application/json" },
        },
    });
    defer req.deinit();

    try req.sendBodyComplete(json_payload.items);

    var response = try req.receiveHead(&.{});

    if (response.head.status != .ok) {
        std.debug.print("API request failed with status: {d}\n", .{@intFromEnum(response.head.status)});
        return error.ApiRequestFailed;
    }

    var body_buf: [1024 * 1024]u8 = undefined;
    const raw_body = try response.reader(&body_buf).*.allocRemaining(allocator, std.Io.Limit.limited(1024 * 1024));
    defer allocator.free(raw_body);

    // Check if it's gzipped.
    const is_gzipped = (raw_body.len >= 2 and raw_body[0] == 0x1f and raw_body[1] == 0x8b);

    if (is_gzipped) {
        var fb_reader = std.Io.Reader.fixed(raw_body);
        var window_buffer: [std.compress.flate.max_window_len]u8 = undefined;
        var decompressor = std.compress.flate.Decompress.init(&fb_reader, .gzip, &window_buffer);
        
        var result: std.ArrayList(u8) = .empty;
        errdefer result.deinit(allocator);
        
        var tmp_buf: [4096]u8 = undefined;
        while (true) {
            const n = try decompressor.reader.readSliceShort(&tmp_buf);
            if (n == 0) break;
            try result.appendSlice(allocator, tmp_buf[0..n]);
        }
        return try result.toOwnedSlice(allocator);
    } else {
        return try allocator.dupe(u8, raw_body);
    }
}

pub fn parseLLMResponse(allocator: std.mem.Allocator, response: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(struct {
        candidates: []struct {
            content: struct {
                parts: []struct {
                    text: []const u8,
                },
            },
        },
    }, allocator, response, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    if (parsed.value.candidates.len > 0 and parsed.value.candidates[0].content.parts.len > 0) {
        return try allocator.dupe(u8, parsed.value.candidates[0].content.parts[0].text);
    } else {
        return error.NoResponse;
    }
}

test "parseLLMResponse basic" {
    const allocator = std.testing.allocator;
    const response = 
        \\{
        \\  "candidates": [
        \\    {
        \\      "content": {
        \\        "parts": [
        \\          {
        \\            "text": "Hello world"
        \\          }
        \\        ]
        \\      }
        \\    }
        \\  ]
        \\}
    ;

    const content = try parseLLMResponse(allocator, response);
    defer allocator.free(content);
    try std.testing.expectEqualStrings("Hello world", content);
}

test "parseLLMResponse no candidates" {
    const allocator = std.testing.allocator;
    const response = 
        \\{
        \\  "candidates": []
        \\}
    ;

    try std.testing.expectError(error.NoResponse, parseLLMResponse(allocator, response));
}


