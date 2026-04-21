const std = @import("std");
const config = @import("config.zig");
const search = @import("search.zig");
const api = @import("api.zig");

const Command = enum {
    config,
    ask,
    search,
    fix,

    pub fn parse(s: []const u8) ?Command {
        if (std.mem.eql(u8, s, "config")) return .config;
        if (std.mem.eql(u8, s, "ask")) return .ask;
        if (std.mem.eql(u8, s, "search")) return .search;
        if (std.mem.eql(u8, s, "fix")) return .fix;
        return null;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command_str = args[1];
    const command = Command.parse(command_str) orelse {
        printUsage();
        return;
    };

    switch (command) {
        .config => try handleConfig(allocator, args[2..]),
        .ask => try handleAsk(allocator, args[2..]),
        .search => try handleSearch(allocator, args[2..]),
        .fix => try handleFix(allocator, args[2..]),
    }
}

fn printUsage() void {
    std.debug.print(
        \\Usage: codeflute <command> [args]
        \\
        \\Commands:
        \\  config set-key <key>    Set the API key
        \\  ask <query>             Ask a question about the codebase
        \\  search <pattern>        Search for a pattern in the codebase
        \\  fix <file> <instr>      Fix a file with an instruction
        \\
    , .{});
}

fn handleConfig(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: codeflute config set-key <key>\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[0], "set-key")) {
        var cfg = try config.Config.load(allocator);
        defer cfg.deinit(allocator);

        allocator.free(cfg.api_key);
        cfg.api_key = try allocator.dupe(u8, args[1]);

        try cfg.save(allocator);
        std.debug.print("API key saved successfully.\n", .{});
    } else {
        std.debug.print("Unknown config subcommand: {s}\n", .{args[0]});
    }
}

fn handleAsk(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: codeflute ask <query>\n", .{});
        return;
    }

    var cfg = try config.Config.load(allocator);
    defer cfg.deinit(allocator);

    if (cfg.api_key.len == 0) {
        std.debug.print("Error: API key not set. Use 'codeflute config set-key <key>'.\n", .{});
        return;
    }

    const query = args[0];
    const response = try api.callLLM(allocator, cfg, query);
    defer allocator.free(response);

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
        std.debug.print("{s}\n", .{parsed.value.candidates[0].content.parts[0].text});
    } else {
        std.debug.print("No response from LLM.\n", .{});
    }
}

fn handleSearch(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 1) {
        std.debug.print("Usage: codeflute search <pattern>\n", .{});
        return;
    }

    const pattern = args[0];
    try search.searchInFiles(allocator, pattern);
}

fn handleFix(allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) {
        std.debug.print("Usage: codeflute fix <file> <instruction>\n", .{});
        return;
    }

    const file_path = args[0];
    const instruction = args[1];

    var cfg = try config.Config.load(allocator);
    defer cfg.deinit(allocator);

    if (cfg.api_key.len == 0) {
        std.debug.print("Error: API key not set. Use 'codeflute config set-key <key>'.\n", .{});
        return;
    }

    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(content);

    const prompt = try std.fmt.allocPrint(allocator, 
        \\Fix the following code according to this instruction: "{s}"
        \\Return ONLY the corrected code, no explanations or markdown backticks.
        \\
        \\Code:
        \\{s}
    , .{ instruction, content });
    defer allocator.free(prompt);

    std.debug.print("Asking LLM to fix {s}...\n", .{file_path});
    const response = try api.callLLM(allocator, cfg, prompt);
    defer allocator.free(response);

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
        const fixed_code = parsed.value.candidates[0].content.parts[0].text;
        
        // Overwrite the file
        const out_file = try std.fs.cwd().createFile(file_path, .{});
        defer out_file.close();
        try out_file.writeAll(fixed_code);
        
        std.debug.print("Successfully fixed {s}.\n", .{file_path});
    } else {
        std.debug.print("No response from LLM.\n", .{});
    }
}
