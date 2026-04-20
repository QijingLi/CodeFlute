//! By convention, root.zig is the root source file when making a library.
const std = @import("std");

pub fn bufferedPrint() !void {
    // Stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try stdout.flush(); // Don't forget to flush!
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn multiply(a: i32, b: i32) i32 {
    return a * b;
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
    try std.testing.expect(add(-1, 1) == 0);
    try std.testing.expect(add(0, 0) == 0);
}

test "basic multiply functionality" {
    try std.testing.expect(multiply(3, 7) == 21);
    try std.testing.expect(multiply(5, 0) == 0);
    try std.testing.expect(multiply(-2, 4) == -8);
    try std.testing.expect(multiply(-3, -5) == 15);
}