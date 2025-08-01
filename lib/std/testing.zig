const std = @import("std.zig");
const builtin = @import("builtin");
const assert = std.debug.assert;
const math = std.math;

/// Provides deterministic randomness in unit tests.
/// Initialized on startup. Read-only after that.
pub var random_seed: u32 = 0;

pub const FailingAllocator = @import("testing/FailingAllocator.zig");
pub const failing_allocator = failing_allocator_instance.allocator();
var failing_allocator_instance = FailingAllocator.init(base_allocator_instance.allocator(), .{
    .fail_index = 0,
});
var base_allocator_instance = std.heap.FixedBufferAllocator.init("");

/// This should only be used in temporary test programs.
pub const allocator = allocator_instance.allocator();
pub var allocator_instance: std.heap.GeneralPurposeAllocator(.{
    .stack_trace_frames = if (std.debug.sys_can_stack_trace) 10 else 0,
    .resize_stack_traces = true,
    // A unique value so that when a default-constructed
    // GeneralPurposeAllocator is incorrectly passed to testing allocator, or
    // vice versa, panic occurs.
    .canary = @truncate(0x2731e675c3a701ba),
}) = b: {
    if (!builtin.is_test) @compileError("testing allocator used when not testing");
    break :b .init;
};

/// TODO https://github.com/ziglang/zig/issues/5738
pub var log_level = std.log.Level.warn;

// Disable printing in tests for simple backends.
pub const backend_can_print = switch (builtin.zig_backend) {
    .stage2_aarch64,
    .stage2_powerpc,
    .stage2_riscv64,
    .stage2_spirv,
    => false,
    else => true,
};

fn print(comptime fmt: []const u8, args: anytype) void {
    if (@inComptime()) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else if (backend_can_print) {
        std.debug.print(fmt, args);
    }
}

/// This function is intended to be used only in tests. It prints diagnostics to stderr
/// and then returns a test failure error when actual_error_union is not expected_error.
pub fn expectError(expected_error: anyerror, actual_error_union: anytype) !void {
    if (actual_error_union) |actual_payload| {
        print("expected error.{s}, found {any}\n", .{ @errorName(expected_error), actual_payload });
        return error.TestExpectedError;
    } else |actual_error| {
        if (expected_error != actual_error) {
            print("expected error.{s}, found error.{s}\n", .{
                @errorName(expected_error),
                @errorName(actual_error),
            });
            return error.TestUnexpectedError;
        }
    }
}

/// This function is intended to be used only in tests. When the two values are not
/// equal, prints diagnostics to stderr to show exactly how they are not equal,
/// then returns a test failure error.
/// `actual` and `expected` are coerced to a common type using peer type resolution.
pub inline fn expectEqual(expected: anytype, actual: anytype) !void {
    const T = @TypeOf(expected, actual);
    return expectEqualInner(T, expected, actual);
}

fn expectEqualInner(comptime T: type, expected: T, actual: T) !void {
    switch (@typeInfo(@TypeOf(actual))) {
        .noreturn,
        .@"opaque",
        .frame,
        .@"anyframe",
        => @compileError("value of type " ++ @typeName(@TypeOf(actual)) ++ " encountered"),

        .undefined,
        .null,
        .void,
        => return,

        .type => {
            if (actual != expected) {
                print("expected type {s}, found type {s}\n", .{ @typeName(expected), @typeName(actual) });
                return error.TestExpectedEqual;
            }
        },

        .bool,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .enum_literal,
        .@"enum",
        .@"fn",
        .error_set,
        => {
            if (actual != expected) {
                print("expected {any}, found {any}\n", .{ expected, actual });
                return error.TestExpectedEqual;
            }
        },

        .pointer => |pointer| {
            switch (pointer.size) {
                .one, .many, .c => {
                    if (actual != expected) {
                        print("expected {*}, found {*}\n", .{ expected, actual });
                        return error.TestExpectedEqual;
                    }
                },
                .slice => {
                    if (actual.ptr != expected.ptr) {
                        print("expected slice ptr {*}, found {*}\n", .{ expected.ptr, actual.ptr });
                        return error.TestExpectedEqual;
                    }
                    if (actual.len != expected.len) {
                        print("expected slice len {}, found {}\n", .{ expected.len, actual.len });
                        return error.TestExpectedEqual;
                    }
                },
            }
        },

        .array => |array| try expectEqualSlices(array.child, &expected, &actual),

        .vector => |info| {
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                if (!std.meta.eql(expected[i], actual[i])) {
                    print("index {d} incorrect. expected {any}, found {any}\n", .{
                        i, expected[i], actual[i],
                    });
                    return error.TestExpectedEqual;
                }
            }
        },

        .@"struct" => |structType| {
            inline for (structType.fields) |field| {
                try expectEqual(@field(expected, field.name), @field(actual, field.name));
            }
        },

        .@"union" => |union_info| {
            if (union_info.tag_type == null) {
                const first_size = @bitSizeOf(union_info.fields[0].type);
                inline for (union_info.fields) |field| {
                    if (@bitSizeOf(field.type) != first_size) {
                        @compileError("Unable to compare untagged unions with varying field sizes for type " ++ @typeName(@TypeOf(actual)));
                    }
                }

                const BackingInt = std.meta.Int(.unsigned, @bitSizeOf(T));
                return expectEqual(
                    @as(BackingInt, @bitCast(expected)),
                    @as(BackingInt, @bitCast(actual)),
                );
            }

            const Tag = std.meta.Tag(@TypeOf(expected));

            const expectedTag = @as(Tag, expected);
            const actualTag = @as(Tag, actual);

            try expectEqual(expectedTag, actualTag);

            // we only reach this switch if the tags are equal
            switch (expected) {
                inline else => |val, tag| try expectEqual(val, @field(actual, @tagName(tag))),
            }
        },

        .optional => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqual(expected_payload, actual_payload);
                } else {
                    print("expected {any}, found null\n", .{expected_payload});
                    return error.TestExpectedEqual;
                }
            } else {
                if (actual) |actual_payload| {
                    print("expected null, found {any}\n", .{actual_payload});
                    return error.TestExpectedEqual;
                }
            }
        },

        .error_union => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqual(expected_payload, actual_payload);
                } else |actual_err| {
                    print("expected {any}, found {}\n", .{ expected_payload, actual_err });
                    return error.TestExpectedEqual;
                }
            } else |expected_err| {
                if (actual) |actual_payload| {
                    print("expected {}, found {any}\n", .{ expected_err, actual_payload });
                    return error.TestExpectedEqual;
                } else |actual_err| {
                    try expectEqual(expected_err, actual_err);
                }
            }
        },
    }
}

test "expectEqual.union(enum)" {
    const T = union(enum) {
        a: i32,
        b: f32,
    };

    const a10 = T{ .a = 10 };

    try expectEqual(a10, a10);
}

test "expectEqual union with comptime-only field" {
    const U = union(enum) {
        a: void,
        b: void,
        c: comptime_int,
    };

    try expectEqual(U{ .a = {} }, .a);
}

test "expectEqual nested array" {
    const a = [2][2]f32{
        [_]f32{ 1.0, 0.0 },
        [_]f32{ 0.0, 1.0 },
    };

    const b = [2][2]f32{
        [_]f32{ 1.0, 0.0 },
        [_]f32{ 0.0, 1.0 },
    };

    try expectEqual(a, b);
}

test "expectEqual vector" {
    const a: @Vector(4, u32) = @splat(4);
    const b: @Vector(4, u32) = @splat(4);

    try expectEqual(a, b);
}

test "expectEqual null" {
    const a = .{null};
    const b = @Vector(1, ?*u8){null};

    try expectEqual(a, b);
}

/// This function is intended to be used only in tests. When the formatted result of the template
/// and its arguments does not equal the expected text, it prints diagnostics to stderr to show how
/// they are not equal, then returns an error. It depends on `expectEqualStrings` for printing
/// diagnostics.
pub fn expectFmt(expected: []const u8, comptime template: []const u8, args: anytype) !void {
    if (@inComptime()) {
        var buffer: [std.fmt.count(template, args)]u8 = undefined;
        return expectEqualStrings(expected, try std.fmt.bufPrint(&buffer, template, args));
    }
    const actual = try std.fmt.allocPrint(allocator, template, args);
    defer allocator.free(actual);
    return expectEqualStrings(expected, actual);
}

/// This function is intended to be used only in tests. When the actual value is
/// not approximately equal to the expected value, prints diagnostics to stderr
/// to show exactly how they are not equal, then returns a test failure error.
/// See `math.approxEqAbs` for more information on the tolerance parameter.
/// The types must be floating-point.
/// `actual` and `expected` are coerced to a common type using peer type resolution.
pub inline fn expectApproxEqAbs(expected: anytype, actual: anytype, tolerance: anytype) !void {
    const T = @TypeOf(expected, actual, tolerance);
    return expectApproxEqAbsInner(T, expected, actual, tolerance);
}

fn expectApproxEqAbsInner(comptime T: type, expected: T, actual: T, tolerance: T) !void {
    switch (@typeInfo(T)) {
        .float => if (!math.approxEqAbs(T, expected, actual, tolerance)) {
            print("actual {}, not within absolute tolerance {} of expected {}\n", .{ actual, tolerance, expected });
            return error.TestExpectedApproxEqAbs;
        },

        .comptime_float => @compileError("Cannot approximately compare two comptime_float values"),

        else => @compileError("Unable to compare non floating point values"),
    }
}

test expectApproxEqAbs {
    inline for ([_]type{ f16, f32, f64, f128 }) |T| {
        const pos_x: T = 12.0;
        const pos_y: T = 12.06;
        const neg_x: T = -12.0;
        const neg_y: T = -12.06;

        try expectApproxEqAbs(pos_x, pos_y, 0.1);
        try expectApproxEqAbs(neg_x, neg_y, 0.1);
    }
}

/// This function is intended to be used only in tests. When the actual value is
/// not approximately equal to the expected value, prints diagnostics to stderr
/// to show exactly how they are not equal, then returns a test failure error.
/// See `math.approxEqRel` for more information on the tolerance parameter.
/// The types must be floating-point.
/// `actual` and `expected` are coerced to a common type using peer type resolution.
pub inline fn expectApproxEqRel(expected: anytype, actual: anytype, tolerance: anytype) !void {
    const T = @TypeOf(expected, actual, tolerance);
    return expectApproxEqRelInner(T, expected, actual, tolerance);
}

fn expectApproxEqRelInner(comptime T: type, expected: T, actual: T, tolerance: T) !void {
    switch (@typeInfo(T)) {
        .float => if (!math.approxEqRel(T, expected, actual, tolerance)) {
            print("actual {}, not within relative tolerance {} of expected {}\n", .{ actual, tolerance, expected });
            return error.TestExpectedApproxEqRel;
        },

        .comptime_float => @compileError("Cannot approximately compare two comptime_float values"),

        else => @compileError("Unable to compare non floating point values"),
    }
}

test expectApproxEqRel {
    inline for ([_]type{ f16, f32, f64, f128 }) |T| {
        const eps_value = comptime math.floatEps(T);
        const sqrt_eps_value = comptime @sqrt(eps_value);

        const pos_x: T = 12.0;
        const pos_y: T = pos_x + 2 * eps_value;
        const neg_x: T = -12.0;
        const neg_y: T = neg_x - 2 * eps_value;

        try expectApproxEqRel(pos_x, pos_y, sqrt_eps_value);
        try expectApproxEqRel(neg_x, neg_y, sqrt_eps_value);
    }
}

/// This function is intended to be used only in tests. When the two slices are not
/// equal, prints diagnostics to stderr to show exactly how they are not equal (with
/// the differences highlighted in red), then returns a test failure error.
/// The colorized output is optional and controlled by the return of `std.io.tty.detectConfig()`.
/// If your inputs are UTF-8 encoded strings, consider calling `expectEqualStrings` instead.
pub fn expectEqualSlices(comptime T: type, expected: []const T, actual: []const T) !void {
    const diff_index: usize = diff_index: {
        const shortest = @min(expected.len, actual.len);
        var index: usize = 0;
        while (index < shortest) : (index += 1) {
            if (!std.meta.eql(actual[index], expected[index])) break :diff_index index;
        }
        break :diff_index if (expected.len == actual.len) return else shortest;
    };
    if (!backend_can_print) return error.TestExpectedEqual;
    const stderr_w = std.debug.lockStderrWriter(&.{});
    defer std.debug.unlockStderrWriter();
    failEqualSlices(T, expected, actual, diff_index, stderr_w) catch {};
    return error.TestExpectedEqual;
}

fn failEqualSlices(
    comptime T: type,
    expected: []const T,
    actual: []const T,
    diff_index: usize,
    w: *std.io.Writer,
) !void {
    try w.print("slices differ. first difference occurs at index {d} (0x{X})\n", .{ diff_index, diff_index });

    // TODO: Should this be configurable by the caller?
    const max_lines: usize = 16;
    const max_window_size: usize = if (T == u8) max_lines * 16 else max_lines;

    // Print a maximum of max_window_size items of each input, starting just before the
    // first difference to give a bit of context.
    var window_start: usize = 0;
    if (@max(actual.len, expected.len) > max_window_size) {
        const alignment = if (T == u8) 16 else 2;
        window_start = std.mem.alignBackward(usize, diff_index - @min(diff_index, alignment), alignment);
    }
    const expected_window = expected[window_start..@min(expected.len, window_start + max_window_size)];
    const expected_truncated = window_start + expected_window.len < expected.len;
    const actual_window = actual[window_start..@min(actual.len, window_start + max_window_size)];
    const actual_truncated = window_start + actual_window.len < actual.len;

    const ttyconf = std.io.tty.detectConfig(.stderr());
    var differ = if (T == u8) BytesDiffer{
        .expected = expected_window,
        .actual = actual_window,
        .ttyconf = ttyconf,
    } else SliceDiffer(T){
        .start_index = window_start,
        .expected = expected_window,
        .actual = actual_window,
        .ttyconf = ttyconf,
    };

    // Print indexes as hex for slices of u8 since it's more likely to be binary data where
    // that is usually useful.
    const index_fmt = if (T == u8) "0x{X}" else "{}";

    try w.print("\n============ expected this output: =============  len: {} (0x{X})\n\n", .{ expected.len, expected.len });
    if (window_start > 0) {
        if (T == u8) {
            try w.print("... truncated, start index: " ++ index_fmt ++ " ...\n", .{window_start});
        } else {
            try w.print("... truncated ...\n", .{});
        }
    }
    differ.write(w) catch {};
    if (expected_truncated) {
        const end_offset = window_start + expected_window.len;
        const num_missing_items = expected.len - (window_start + expected_window.len);
        if (T == u8) {
            try w.print("... truncated, indexes [" ++ index_fmt ++ "..] not shown, remaining bytes: " ++ index_fmt ++ " ...\n", .{ end_offset, num_missing_items });
        } else {
            try w.print("... truncated, remaining items: " ++ index_fmt ++ " ...\n", .{num_missing_items});
        }
    }

    // now reverse expected/actual and print again
    differ.expected = actual_window;
    differ.actual = expected_window;
    try w.print("\n============= instead found this: ==============  len: {} (0x{X})\n\n", .{ actual.len, actual.len });
    if (window_start > 0) {
        if (T == u8) {
            try w.print("... truncated, start index: " ++ index_fmt ++ " ...\n", .{window_start});
        } else {
            try w.print("... truncated ...\n", .{});
        }
    }
    differ.write(w) catch {};
    if (actual_truncated) {
        const end_offset = window_start + actual_window.len;
        const num_missing_items = actual.len - (window_start + actual_window.len);
        if (T == u8) {
            try w.print("... truncated, indexes [" ++ index_fmt ++ "..] not shown, remaining bytes: " ++ index_fmt ++ " ...\n", .{ end_offset, num_missing_items });
        } else {
            try w.print("... truncated, remaining items: " ++ index_fmt ++ " ...\n", .{num_missing_items});
        }
    }
    try w.print("\n================================================\n\n", .{});

    return error.TestExpectedEqual;
}

fn SliceDiffer(comptime T: type) type {
    return struct {
        start_index: usize,
        expected: []const T,
        actual: []const T,
        ttyconf: std.io.tty.Config,

        const Self = @This();

        pub fn write(self: Self, writer: *std.io.Writer) !void {
            for (self.expected, 0..) |value, i| {
                const full_index = self.start_index + i;
                const diff = if (i < self.actual.len) !std.meta.eql(self.actual[i], value) else true;
                if (diff) try self.ttyconf.setColor(writer, .red);
                if (@typeInfo(T) == .pointer) {
                    try writer.print("[{}]{*}: {any}\n", .{ full_index, value, value });
                } else {
                    try writer.print("[{}]: {any}\n", .{ full_index, value });
                }
                if (diff) try self.ttyconf.setColor(writer, .reset);
            }
        }
    };
}

const BytesDiffer = struct {
    expected: []const u8,
    actual: []const u8,
    ttyconf: std.io.tty.Config,

    pub fn write(self: BytesDiffer, writer: *std.io.Writer) !void {
        var expected_iterator = std.mem.window(u8, self.expected, 16, 16);
        var row: usize = 0;
        while (expected_iterator.next()) |chunk| {
            // to avoid having to calculate diffs twice per chunk
            var diffs: std.bit_set.IntegerBitSet(16) = .{ .mask = 0 };
            for (chunk, 0..) |byte, col| {
                const absolute_byte_index = col + row * 16;
                const diff = if (absolute_byte_index < self.actual.len) self.actual[absolute_byte_index] != byte else true;
                if (diff) diffs.set(col);
                try self.writeDiff(writer, "{X:0>2} ", .{byte}, diff);
                if (col == 7) try writer.writeByte(' ');
            }
            try writer.writeByte(' ');
            if (chunk.len < 16) {
                var missing_columns = (16 - chunk.len) * 3;
                if (chunk.len < 8) missing_columns += 1;
                try writer.splatByteAll(' ', missing_columns);
            }
            for (chunk, 0..) |byte, col| {
                const diff = diffs.isSet(col);
                if (std.ascii.isPrint(byte)) {
                    try self.writeDiff(writer, "{c}", .{byte}, diff);
                } else {
                    // TODO: remove this `if` when https://github.com/ziglang/zig/issues/7600 is fixed
                    if (self.ttyconf == .windows_api) {
                        try self.writeDiff(writer, ".", .{}, diff);
                        continue;
                    }

                    // Let's print some common control codes as graphical Unicode symbols.
                    // We don't want to do this for all control codes because most control codes apart from
                    // the ones that Zig has escape sequences for are likely not very useful to print as symbols.
                    switch (byte) {
                        '\n' => try self.writeDiff(writer, "␊", .{}, diff),
                        '\r' => try self.writeDiff(writer, "␍", .{}, diff),
                        '\t' => try self.writeDiff(writer, "␉", .{}, diff),
                        else => try self.writeDiff(writer, ".", .{}, diff),
                    }
                }
            }
            try writer.writeByte('\n');
            row += 1;
        }
    }

    fn writeDiff(self: BytesDiffer, writer: *std.io.Writer, comptime fmt: []const u8, args: anytype, diff: bool) !void {
        if (diff) try self.ttyconf.setColor(writer, .red);
        try writer.print(fmt, args);
        if (diff) try self.ttyconf.setColor(writer, .reset);
    }
};

test {
    try expectEqualSlices(u8, "foo\x00", "foo\x00");
    try expectEqualSlices(u16, &[_]u16{ 100, 200, 300, 400 }, &[_]u16{ 100, 200, 300, 400 });
    const E = enum { foo, bar };
    const S = struct {
        v: E,
    };
    try expectEqualSlices(
        S,
        &[_]S{ .{ .v = .foo }, .{ .v = .bar }, .{ .v = .foo }, .{ .v = .bar } },
        &[_]S{ .{ .v = .foo }, .{ .v = .bar }, .{ .v = .foo }, .{ .v = .bar } },
    );
}

/// This function is intended to be used only in tests. Checks that two slices or two arrays are equal,
/// including that their sentinel (if any) are the same. Will error if given another type.
pub fn expectEqualSentinel(comptime T: type, comptime sentinel: T, expected: [:sentinel]const T, actual: [:sentinel]const T) !void {
    try expectEqualSlices(T, expected, actual);

    const expected_value_sentinel = blk: {
        switch (@typeInfo(@TypeOf(expected))) {
            .pointer => {
                break :blk expected[expected.len];
            },
            .array => |array_info| {
                const indexable_outside_of_bounds = @as([]const array_info.child, &expected);
                break :blk indexable_outside_of_bounds[indexable_outside_of_bounds.len];
            },
            else => {},
        }
    };

    const actual_value_sentinel = blk: {
        switch (@typeInfo(@TypeOf(actual))) {
            .pointer => {
                break :blk actual[actual.len];
            },
            .array => |array_info| {
                const indexable_outside_of_bounds = @as([]const array_info.child, &actual);
                break :blk indexable_outside_of_bounds[indexable_outside_of_bounds.len];
            },
            else => {},
        }
    };

    if (!std.meta.eql(sentinel, expected_value_sentinel)) {
        print("expectEqualSentinel: 'expected' sentinel in memory is different from its type sentinel. type sentinel {}, in memory sentinel {}\n", .{ sentinel, expected_value_sentinel });
        return error.TestExpectedEqual;
    }

    if (!std.meta.eql(sentinel, actual_value_sentinel)) {
        print("expectEqualSentinel: 'actual' sentinel in memory is different from its type sentinel. type sentinel {}, in memory sentinel {}\n", .{ sentinel, actual_value_sentinel });
        return error.TestExpectedEqual;
    }
}

/// This function is intended to be used only in tests.
/// When `ok` is false, returns a test failure error.
pub fn expect(ok: bool) !void {
    if (!ok) return error.TestUnexpectedResult;
}

pub const TmpDir = struct {
    dir: std.fs.Dir,
    parent_dir: std.fs.Dir,
    sub_path: [sub_path_len]u8,

    const random_bytes_count = 12;
    const sub_path_len = std.fs.base64_encoder.calcSize(random_bytes_count);

    pub fn cleanup(self: *TmpDir) void {
        self.dir.close();
        self.parent_dir.deleteTree(&self.sub_path) catch {};
        self.parent_dir.close();
        self.* = undefined;
    }
};

pub fn tmpDir(opts: std.fs.Dir.OpenOptions) TmpDir {
    var random_bytes: [TmpDir.random_bytes_count]u8 = undefined;
    std.crypto.random.bytes(&random_bytes);
    var sub_path: [TmpDir.sub_path_len]u8 = undefined;
    _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);

    const cwd = std.fs.cwd();
    var cache_dir = cwd.makeOpenPath(".zig-cache", .{}) catch
        @panic("unable to make tmp dir for testing: unable to make and open .zig-cache dir");
    defer cache_dir.close();
    const parent_dir = cache_dir.makeOpenPath("tmp", .{}) catch
        @panic("unable to make tmp dir for testing: unable to make and open .zig-cache/tmp dir");
    const dir = parent_dir.makeOpenPath(&sub_path, opts) catch
        @panic("unable to make tmp dir for testing: unable to make and open the tmp dir");

    return .{
        .dir = dir,
        .parent_dir = parent_dir,
        .sub_path = sub_path,
    };
}

pub fn expectEqualStrings(expected: []const u8, actual: []const u8) !void {
    if (std.mem.indexOfDiff(u8, actual, expected)) |diff_index| {
        if (@inComptime()) {
            @compileError(std.fmt.comptimePrint("\nexpected:\n{s}\nfound:\n{s}\ndifference starts at index {d}", .{
                expected, actual, diff_index,
            }));
        }
        print("\n====== expected this output: =========\n", .{});
        printWithVisibleNewlines(expected);
        print("\n======== instead found this: =========\n", .{});
        printWithVisibleNewlines(actual);
        print("\n======================================\n", .{});

        var diff_line_number: usize = 1;
        for (expected[0..diff_index]) |value| {
            if (value == '\n') diff_line_number += 1;
        }
        print("First difference occurs on line {d}:\n", .{diff_line_number});

        print("expected:\n", .{});
        printIndicatorLine(expected, diff_index);

        print("found:\n", .{});
        printIndicatorLine(actual, diff_index);

        return error.TestExpectedEqual;
    }
}

pub fn expectStringStartsWith(actual: []const u8, expected_starts_with: []const u8) !void {
    if (std.mem.startsWith(u8, actual, expected_starts_with))
        return;

    const shortened_actual = if (actual.len >= expected_starts_with.len)
        actual[0..expected_starts_with.len]
    else
        actual;

    print("\n====== expected to start with: =========\n", .{});
    printWithVisibleNewlines(expected_starts_with);
    print("\n====== instead started with: ===========\n", .{});
    printWithVisibleNewlines(shortened_actual);
    print("\n========= full output: ==============\n", .{});
    printWithVisibleNewlines(actual);
    print("\n======================================\n", .{});

    return error.TestExpectedStartsWith;
}

pub fn expectStringEndsWith(actual: []const u8, expected_ends_with: []const u8) !void {
    if (std.mem.endsWith(u8, actual, expected_ends_with))
        return;

    const shortened_actual = if (actual.len >= expected_ends_with.len)
        actual[(actual.len - expected_ends_with.len)..]
    else
        actual;

    print("\n====== expected to end with: =========\n", .{});
    printWithVisibleNewlines(expected_ends_with);
    print("\n====== instead ended with: ===========\n", .{});
    printWithVisibleNewlines(shortened_actual);
    print("\n========= full output: ==============\n", .{});
    printWithVisibleNewlines(actual);
    print("\n======================================\n", .{});

    return error.TestExpectedEndsWith;
}

/// This function is intended to be used only in tests. When the two values are not
/// deeply equal, prints diagnostics to stderr to show exactly how they are not equal,
/// then returns a test failure error.
/// `actual` and `expected` are coerced to a common type using peer type resolution.
///
/// Deeply equal is defined as follows:
/// Primitive types are deeply equal if they are equal using `==` operator.
/// Struct values are deeply equal if their corresponding fields are deeply equal.
/// Container types(like Array/Slice/Vector) deeply equal when their corresponding elements are deeply equal.
/// Pointer values are deeply equal if values they point to are deeply equal.
///
/// Note: Self-referential structs are supported (e.g. things like std.SinglyLinkedList)
/// but may cause infinite recursion or stack overflow when a container has a pointer to itself.
pub inline fn expectEqualDeep(expected: anytype, actual: anytype) error{TestExpectedEqual}!void {
    const T = @TypeOf(expected, actual);
    return expectEqualDeepInner(T, expected, actual);
}

fn expectEqualDeepInner(comptime T: type, expected: T, actual: T) error{TestExpectedEqual}!void {
    switch (@typeInfo(@TypeOf(actual))) {
        .noreturn,
        .@"opaque",
        .frame,
        .@"anyframe",
        => @compileError("value of type " ++ @typeName(@TypeOf(actual)) ++ " encountered"),

        .undefined,
        .null,
        .void,
        => return,

        .type => {
            if (actual != expected) {
                print("expected type {s}, found type {s}\n", .{ @typeName(expected), @typeName(actual) });
                return error.TestExpectedEqual;
            }
        },

        .bool,
        .int,
        .float,
        .comptime_float,
        .comptime_int,
        .enum_literal,
        .@"enum",
        .@"fn",
        .error_set,
        => {
            if (actual != expected) {
                print("expected {}, found {}\n", .{ expected, actual });
                return error.TestExpectedEqual;
            }
        },

        .pointer => |pointer| {
            switch (pointer.size) {
                // We have no idea what is behind those pointers, so the best we can do is `==` check.
                .c, .many => {
                    if (actual != expected) {
                        print("expected {*}, found {*}\n", .{ expected, actual });
                        return error.TestExpectedEqual;
                    }
                },
                .one => {
                    // Length of those pointers are runtime value, so the best we can do is `==` check.
                    switch (@typeInfo(pointer.child)) {
                        .@"fn", .@"opaque" => {
                            if (actual != expected) {
                                print("expected {*}, found {*}\n", .{ expected, actual });
                                return error.TestExpectedEqual;
                            }
                        },
                        else => try expectEqualDeep(expected.*, actual.*),
                    }
                },
                .slice => {
                    if (expected.len != actual.len) {
                        print("Slice len not the same, expected {d}, found {d}\n", .{ expected.len, actual.len });
                        return error.TestExpectedEqual;
                    }
                    var i: usize = 0;
                    while (i < expected.len) : (i += 1) {
                        expectEqualDeep(expected[i], actual[i]) catch |e| {
                            print("index {d} incorrect. expected {any}, found {any}\n", .{
                                i, expected[i], actual[i],
                            });
                            return e;
                        };
                    }
                },
            }
        },

        .array => |_| {
            if (expected.len != actual.len) {
                print("Array len not the same, expected {d}, found {d}\n", .{ expected.len, actual.len });
                return error.TestExpectedEqual;
            }
            var i: usize = 0;
            while (i < expected.len) : (i += 1) {
                expectEqualDeep(expected[i], actual[i]) catch |e| {
                    print("index {d} incorrect. expected {any}, found {any}\n", .{
                        i, expected[i], actual[i],
                    });
                    return e;
                };
            }
        },

        .vector => |info| {
            if (info.len != @typeInfo(@TypeOf(actual)).vector.len) {
                print("Vector len not the same, expected {d}, found {d}\n", .{ info.len, @typeInfo(@TypeOf(actual)).vector.len });
                return error.TestExpectedEqual;
            }
            var i: usize = 0;
            while (i < info.len) : (i += 1) {
                expectEqualDeep(expected[i], actual[i]) catch |e| {
                    print("index {d} incorrect. expected {any}, found {any}\n", .{
                        i, expected[i], actual[i],
                    });
                    return e;
                };
            }
        },

        .@"struct" => |structType| {
            inline for (structType.fields) |field| {
                expectEqualDeep(@field(expected, field.name), @field(actual, field.name)) catch |e| {
                    print("Field {s} incorrect. expected {any}, found {any}\n", .{ field.name, @field(expected, field.name), @field(actual, field.name) });
                    return e;
                };
            }
        },

        .@"union" => |union_info| {
            if (union_info.tag_type == null) {
                @compileError("Unable to compare untagged union values for type " ++ @typeName(@TypeOf(actual)));
            }

            const Tag = std.meta.Tag(@TypeOf(expected));

            const expectedTag = @as(Tag, expected);
            const actualTag = @as(Tag, actual);

            try expectEqual(expectedTag, actualTag);

            // we only reach this switch if the tags are equal
            switch (expected) {
                inline else => |val, tag| {
                    try expectEqualDeep(val, @field(actual, @tagName(tag)));
                },
            }
        },

        .optional => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqualDeep(expected_payload, actual_payload);
                } else {
                    print("expected {any}, found null\n", .{expected_payload});
                    return error.TestExpectedEqual;
                }
            } else {
                if (actual) |actual_payload| {
                    print("expected null, found {any}\n", .{actual_payload});
                    return error.TestExpectedEqual;
                }
            }
        },

        .error_union => {
            if (expected) |expected_payload| {
                if (actual) |actual_payload| {
                    try expectEqualDeep(expected_payload, actual_payload);
                } else |actual_err| {
                    print("expected {any}, found {any}\n", .{ expected_payload, actual_err });
                    return error.TestExpectedEqual;
                }
            } else |expected_err| {
                if (actual) |actual_payload| {
                    print("expected {any}, found {any}\n", .{ expected_err, actual_payload });
                    return error.TestExpectedEqual;
                } else |actual_err| {
                    try expectEqualDeep(expected_err, actual_err);
                }
            }
        },
    }
}

test "expectEqualDeep primitive type" {
    try expectEqualDeep(1, 1);
    try expectEqualDeep(true, true);
    try expectEqualDeep(1.5, 1.5);
    try expectEqualDeep(u8, u8);
    try expectEqualDeep(error.Bad, error.Bad);

    // optional
    {
        const foo: ?u32 = 1;
        const bar: ?u32 = 1;
        try expectEqualDeep(foo, bar);
        try expectEqualDeep(?u32, ?u32);
    }
    // function type
    {
        const fnType = struct {
            fn foo() void {
                unreachable;
            }
        }.foo;
        try expectEqualDeep(fnType, fnType);
    }
}

test "expectEqualDeep pointer" {
    const a = 1;
    const b = 1;
    try expectEqualDeep(&a, &b);
}

test "expectEqualDeep composite type" {
    try expectEqualDeep("abc", "abc");
    const s1: []const u8 = "abc";
    const s2 = "abcd";
    const s3: []const u8 = s2[0..3];
    try expectEqualDeep(s1, s3);

    const TestStruct = struct { s: []const u8 };
    try expectEqualDeep(TestStruct{ .s = "abc" }, TestStruct{ .s = "abc" });
    try expectEqualDeep([_][]const u8{ "a", "b", "c" }, [_][]const u8{ "a", "b", "c" });

    // vector
    try expectEqualDeep(@as(@Vector(4, u32), @splat(4)), @as(@Vector(4, u32), @splat(4)));

    // nested array
    {
        const a = [2][2]f32{
            [_]f32{ 1.0, 0.0 },
            [_]f32{ 0.0, 1.0 },
        };

        const b = [2][2]f32{
            [_]f32{ 1.0, 0.0 },
            [_]f32{ 0.0, 1.0 },
        };

        try expectEqualDeep(a, b);
        try expectEqualDeep(&a, &b);
    }

    // inferred union
    const TestStruct2 = struct {
        const A = union(enum) { b: B, c: C };
        const B = struct {};
        const C = struct { a: *const A };
    };

    const union1 = TestStruct2.A{ .b = .{} };
    try expectEqualDeep(
        TestStruct2.A{ .c = .{ .a = &union1 } },
        TestStruct2.A{ .c = .{ .a = &union1 } },
    );
}

fn printIndicatorLine(source: []const u8, indicator_index: usize) void {
    const line_begin_index = if (std.mem.lastIndexOfScalar(u8, source[0..indicator_index], '\n')) |line_begin|
        line_begin + 1
    else
        0;
    const line_end_index = if (std.mem.indexOfScalar(u8, source[indicator_index..], '\n')) |line_end|
        (indicator_index + line_end)
    else
        source.len;

    printLine(source[line_begin_index..line_end_index]);
    for (line_begin_index..indicator_index) |_|
        print(" ", .{});
    if (indicator_index >= source.len)
        print("^ (end of string)\n", .{})
    else
        print("^ ('\\x{x:0>2}')\n", .{source[indicator_index]});
}

fn printWithVisibleNewlines(source: []const u8) void {
    var i: usize = 0;
    while (std.mem.indexOfScalar(u8, source[i..], '\n')) |nl| : (i += nl + 1) {
        printLine(source[i..][0..nl]);
    }
    print("{s}␃\n", .{source[i..]}); // End of Text symbol (ETX)
}

fn printLine(line: []const u8) void {
    if (line.len != 0) switch (line[line.len - 1]) {
        ' ', '\t' => return print("{s}⏎\n", .{line}), // Return symbol
        else => {},
    };
    print("{s}\n", .{line});
}

test {
    try expectEqualStrings("foo", "foo");
}

/// Exhaustively check that allocation failures within `test_fn` are handled without
/// introducing memory leaks. If used with the `testing.allocator` as the `backing_allocator`,
/// it will also be able to detect double frees, etc (when runtime safety is enabled).
///
/// The provided `test_fn` must have a `std.mem.Allocator` as its first argument,
/// and must have a return type of `!void`. Any extra arguments of `test_fn` can
/// be provided via the `extra_args` tuple.
///
/// Any relevant state shared between runs of `test_fn` *must* be reset within `test_fn`.
///
/// The strategy employed is to:
/// - Run the test function once to get the total number of allocations.
/// - Then, iterate and run the function X more times, incrementing
///   the failing index each iteration (where X is the total number of
///   allocations determined previously)
///
/// Expects that `test_fn` has a deterministic number of memory allocations:
/// - If an allocation was made to fail during a run of `test_fn`, but `test_fn`
///   didn't return `error.OutOfMemory`, then `error.SwallowedOutOfMemoryError`
///   is returned from `checkAllAllocationFailures`. You may want to ignore this
///   depending on whether or not the code you're testing includes some strategies
///   for recovering from `error.OutOfMemory`.
/// - If a run of `test_fn` with an expected allocation failure executes without
///   an allocation failure being induced, then `error.NondeterministicMemoryUsage`
///   is returned. This error means that there are allocation points that won't be
///   tested by the strategy this function employs (that is, there are sometimes more
///   points of allocation than the initial run of `test_fn` detects).
///
/// ---
///
/// Here's an example using a simple test case that will cause a leak when the
/// allocation of `bar` fails (but will pass normally):
///
/// ```zig
/// test {
///     const length: usize = 10;
///     const allocator = std.testing.allocator;
///     var foo = try allocator.alloc(u8, length);
///     var bar = try allocator.alloc(u8, length);
///
///     allocator.free(foo);
///     allocator.free(bar);
/// }
/// ```
///
/// The test case can be converted to something that this function can use by
/// doing:
///
/// ```zig
/// fn testImpl(allocator: std.mem.Allocator, length: usize) !void {
///     var foo = try allocator.alloc(u8, length);
///     var bar = try allocator.alloc(u8, length);
///
///     allocator.free(foo);
///     allocator.free(bar);
/// }
///
/// test {
///     const length: usize = 10;
///     const allocator = std.testing.allocator;
///     try std.testing.checkAllAllocationFailures(allocator, testImpl, .{length});
/// }
/// ```
///
/// Running this test will show that `foo` is leaked when the allocation of
/// `bar` fails. The simplest fix, in this case, would be to use defer like so:
///
/// ```zig
/// fn testImpl(allocator: std.mem.Allocator, length: usize) !void {
///     var foo = try allocator.alloc(u8, length);
///     defer allocator.free(foo);
///     var bar = try allocator.alloc(u8, length);
///     defer allocator.free(bar);
/// }
/// ```
pub fn checkAllAllocationFailures(backing_allocator: std.mem.Allocator, comptime test_fn: anytype, extra_args: anytype) !void {
    switch (@typeInfo(@typeInfo(@TypeOf(test_fn)).@"fn".return_type.?)) {
        .error_union => |info| {
            if (info.payload != void) {
                @compileError("Return type must be !void");
            }
        },
        else => @compileError("Return type must be !void"),
    }
    if (@typeInfo(@TypeOf(extra_args)) != .@"struct") {
        @compileError("Expected tuple or struct argument, found " ++ @typeName(@TypeOf(extra_args)));
    }

    const ArgsTuple = std.meta.ArgsTuple(@TypeOf(test_fn));
    const fn_args_fields = @typeInfo(ArgsTuple).@"struct".fields;
    if (fn_args_fields.len == 0 or fn_args_fields[0].type != std.mem.Allocator) {
        @compileError("The provided function must have an " ++ @typeName(std.mem.Allocator) ++ " as its first argument");
    }
    const expected_args_tuple_len = fn_args_fields.len - 1;
    if (extra_args.len != expected_args_tuple_len) {
        @compileError("The provided function expects " ++ std.fmt.comptimePrint("{d}", .{expected_args_tuple_len}) ++ " extra arguments, but the provided tuple contains " ++ std.fmt.comptimePrint("{d}", .{extra_args.len}));
    }

    // Setup the tuple that will actually be used with @call (we'll need to insert
    // the failing allocator in field @"0" before each @call)
    var args: ArgsTuple = undefined;
    inline for (@typeInfo(@TypeOf(extra_args)).@"struct".fields, 0..) |field, i| {
        const arg_i_str = comptime str: {
            var str_buf: [100]u8 = undefined;
            const args_i = i + 1;
            const str_len = std.fmt.printInt(&str_buf, args_i, 10, .lower, .{});
            break :str str_buf[0..str_len];
        };
        @field(args, arg_i_str) = @field(extra_args, field.name);
    }

    // Try it once with unlimited memory, make sure it works
    const needed_alloc_count = x: {
        var failing_allocator_inst = std.testing.FailingAllocator.init(backing_allocator, .{});
        args.@"0" = failing_allocator_inst.allocator();

        try @call(.auto, test_fn, args);
        break :x failing_allocator_inst.alloc_index;
    };

    var fail_index: usize = 0;
    while (fail_index < needed_alloc_count) : (fail_index += 1) {
        var failing_allocator_inst = std.testing.FailingAllocator.init(backing_allocator, .{ .fail_index = fail_index });
        args.@"0" = failing_allocator_inst.allocator();

        if (@call(.auto, test_fn, args)) |_| {
            if (failing_allocator_inst.has_induced_failure) {
                return error.SwallowedOutOfMemoryError;
            } else {
                return error.NondeterministicMemoryUsage;
            }
        } else |err| switch (err) {
            error.OutOfMemory => {
                if (failing_allocator_inst.allocated_bytes != failing_allocator_inst.freed_bytes) {
                    print(
                        "\nfail_index: {d}/{d}\nallocated bytes: {d}\nfreed bytes: {d}\nallocations: {d}\ndeallocations: {d}\nallocation that was made to fail: {f}",
                        .{
                            fail_index,
                            needed_alloc_count,
                            failing_allocator_inst.allocated_bytes,
                            failing_allocator_inst.freed_bytes,
                            failing_allocator_inst.allocations,
                            failing_allocator_inst.deallocations,
                            failing_allocator_inst.getStackTrace(),
                        },
                    );
                    return error.MemoryLeakDetected;
                }
            },
            else => return err,
        }
    }
}

/// Given a type, references all the declarations inside, so that the semantic analyzer sees them.
pub fn refAllDecls(comptime T: type) void {
    if (!builtin.is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        _ = &@field(T, decl.name);
    }
}

/// Given a type, recursively references all the declarations inside, so that the semantic analyzer sees them.
/// For deep types, you may use `@setEvalBranchQuota`.
pub fn refAllDeclsRecursive(comptime T: type) void {
    if (!builtin.is_test) return;
    inline for (comptime std.meta.declarations(T)) |decl| {
        if (@TypeOf(@field(T, decl.name)) == type) {
            switch (@typeInfo(@field(T, decl.name))) {
                .@"struct", .@"enum", .@"union", .@"opaque" => refAllDeclsRecursive(@field(T, decl.name)),
                else => {},
            }
        }
        _ = &@field(T, decl.name);
    }
}

pub const FuzzInputOptions = struct {
    corpus: []const []const u8 = &.{},
};

/// Inline to avoid coverage instrumentation.
pub inline fn fuzz(
    context: anytype,
    comptime testOne: fn (context: @TypeOf(context), input: []const u8) anyerror!void,
    options: FuzzInputOptions,
) anyerror!void {
    return @import("root").fuzz(context, testOne, options);
}

/// A `std.Io.Reader` that writes a predetermined list of buffers during `stream`.
pub const Reader = struct {
    calls: []const Call,
    interface: std.Io.Reader,
    next_call_index: usize,
    next_offset: usize,
    /// Further reduces how many bytes are written in each `stream` call.
    artificial_limit: std.Io.Limit = .unlimited,

    pub const Call = struct {
        buffer: []const u8,
    };

    pub fn init(buffer: []u8, calls: []const Call) Reader {
        return .{
            .next_call_index = 0,
            .next_offset = 0,
            .interface = .{
                .vtable = &.{ .stream = stream },
                .buffer = buffer,
                .seek = 0,
                .end = 0,
            },
            .calls = calls,
        };
    }

    fn stream(io_r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const r: *Reader = @alignCast(@fieldParentPtr("interface", io_r));
        if (r.calls.len - r.next_call_index == 0) return error.EndOfStream;
        const call = r.calls[r.next_call_index];
        const buffer = r.artificial_limit.sliceConst(limit.sliceConst(call.buffer[r.next_offset..]));
        const n = try w.write(buffer);
        r.next_offset += n;
        if (call.buffer.len - r.next_offset == 0) {
            r.next_call_index += 1;
            r.next_offset = 0;
        }
        return n;
    }
};
