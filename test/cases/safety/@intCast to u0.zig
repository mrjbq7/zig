const std = @import("std");

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    _ = stack_trace;
    if (std.mem.eql(u8, message, "integer does not fit in destination type")) {
        std.process.exit(0);
    }
    std.process.exit(1);
}

pub fn main() !void {
    bar(1, 1);
    return error.TestFailed;
}

fn bar(one: u1, not_zero: i32) void {
    const x = one << @intCast(not_zero);
    _ = x;
}
// run
// backend=stage2,llvm
// target=x86_64-linux,aarch64-linux
