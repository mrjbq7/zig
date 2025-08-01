const builtin = @import("builtin");
const std = @import("std");
const assert = std.debug.assert;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;
const maxInt = std.math.maxInt;
const minInt = std.math.minInt;
const mem = std.mem;
const math = std.math;

test "assignment operators" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    var i: u32 = 0;
    i += 5;
    try expect(i == 5);
    i -= 2;
    try expect(i == 3);
    i *= 20;
    try expect(i == 60);
    i /= 3;
    try expect(i == 20);
    i %= 11;
    try expect(i == 9);
    i <<= 1;
    try expect(i == 18);
    i >>= 2;
    try expect(i == 4);
    i = 6;
    i &= 5;
    try expect(i == 4);
    i ^= 6;
    try expect(i == 2);
    i = 6;
    i |= 3;
    try expect(i == 7);
}

test "three expr in a row" {
    try testThreeExprInARow(false, true);
    try comptime testThreeExprInARow(false, true);
}
fn testThreeExprInARow(f: bool, t: bool) !void {
    try assertFalse(f or f or f);
    try assertFalse(t and t and f);
    try assertFalse(1 | 2 | 4 != 7);
    try assertFalse(3 ^ 6 ^ 8 != 13);
    try assertFalse(7 & 14 & 28 != 4);
    try assertFalse(9 << 1 << 2 != 9 << 3);
    try assertFalse(90 >> 1 >> 2 != 90 >> 3);
    try assertFalse(100 - 1 + 1000 != 1099);
    try assertFalse(5 * 4 / 2 % 3 != 1);
    try assertFalse(@as(i32, @as(i32, 5)) != 5);
    try assertFalse(!!false);
    try assertFalse(@as(i32, 7) != --(@as(i32, 7)));
}
fn assertFalse(b: bool) !void {
    try expect(!b);
}

test "@clz" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    try testClz();
    try comptime testClz();
}

fn testClz() !void {
    try expect(testOneClz(u8, 0b10001010) == 0);
    try expect(testOneClz(u8, 0b00001010) == 4);
    try expect(testOneClz(u8, 0b00011010) == 3);
    try expect(testOneClz(u8, 0b00000000) == 8);
    try expect(testOneClz(i8, -1) == 0);
}

test "@clz big ints" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testClzBigInts();
    try comptime testClzBigInts();
}

fn testClzBigInts() !void {
    try expect(testOneClz(u128, 0xffffffffffffffff) == 64);
    try expect(testOneClz(u128, 0x10000000000000000) == 63);
}

fn testOneClz(comptime T: type, x: T) u32 {
    return @clz(x);
}

test "@clz vectors" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testClzVectors();
    try comptime testClzVectors();
}

fn testClzVectors() !void {
    const Vu4 = @Vector(64, u4);
    const Vu8 = @Vector(64, u8);
    const Vu128 = @Vector(64, u128);

    @setEvalBranchQuota(10_000);
    try testOneClzVector(u8, 64, @as(Vu8, @splat(0b10001010)), @as(Vu4, @splat(0)));
    try testOneClzVector(u8, 64, @as(Vu8, @splat(0b00001010)), @as(Vu4, @splat(4)));
    try testOneClzVector(u8, 64, @as(Vu8, @splat(0b00011010)), @as(Vu4, @splat(3)));
    try testOneClzVector(u8, 64, @as(Vu8, @splat(0b00000000)), @as(Vu4, @splat(8)));
    try testOneClzVector(u128, 64, @as(Vu128, @splat(0xffffffffffffffff)), @as(Vu8, @splat(64)));
    try testOneClzVector(u128, 64, @as(Vu128, @splat(0x10000000000000000)), @as(Vu8, @splat(63)));
}

fn testOneClzVector(
    comptime T: type,
    comptime len: u32,
    x: @Vector(len, T),
    expected: @Vector(len, u32),
) !void {
    try expectVectorsEqual(@clz(x), expected);
}

fn expectVectorsEqual(a: anytype, b: anytype) !void {
    const len_a = @typeInfo(@TypeOf(a)).vector.len;
    const len_b = @typeInfo(@TypeOf(b)).vector.len;
    try expect(len_a == len_b);

    var i: usize = 0;
    while (i < len_a) : (i += 1) {
        try expect(a[i] == b[i]);
    }
}

test "@ctz" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testCtz();
    try comptime testCtz();
}

fn testCtz() !void {
    try expect(testOneCtz(u8, 0b10100000) == 5);
    try expect(testOneCtz(u8, 0b10001010) == 1);
    try expect(testOneCtz(u8, 0b00000000) == 8);
    try expect(testOneCtz(i8, -1) == 0);
    try expect(testOneCtz(i8, -2) == 1);
    try expect(testOneCtz(u16, 0b00000000) == 16);
}

fn testOneCtz(comptime T: type, x: T) u32 {
    return @ctz(x);
}

test "@ctz 128-bit integers" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testCtz128();
    try comptime testCtz128();
}

fn testCtz128() !void {
    try expect(testOneCtz(u128, @as(u128, 0x40000000000000000000000000000000)) == 126);
    try expect(math.rotl(u128, @as(u128, 0x40000000000000000000000000000000), @as(u8, 1)) == @as(u128, 0x80000000000000000000000000000000));
    try expect(testOneCtz(u128, @as(u128, 0x80000000000000000000000000000000)) == 127);
    try expect(testOneCtz(u128, math.rotl(u128, @as(u128, 0x40000000000000000000000000000000), @as(u8, 1))) == 127);
}

test "@ctz vectors" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testCtzVectors();
    try comptime testCtzVectors();
}

fn testCtzVectors() !void {
    const Vu4 = @Vector(64, u4);
    const Vu8 = @Vector(64, u8);
    @setEvalBranchQuota(10_000);
    try testOneCtzVector(u8, 64, @as(Vu8, @splat(0b10100000)), @as(Vu4, @splat(5)));
    try testOneCtzVector(u8, 64, @as(Vu8, @splat(0b10001010)), @as(Vu4, @splat(1)));
    try testOneCtzVector(u8, 64, @as(Vu8, @splat(0b00000000)), @as(Vu4, @splat(8)));
    try testOneCtzVector(u16, 64, @as(@Vector(64, u16), @splat(0b00000000)), @as(@Vector(64, u5), @splat(16)));
}

fn testOneCtzVector(
    comptime T: type,
    comptime len: u32,
    x: @Vector(len, T),
    expected: @Vector(len, u32),
) !void {
    try expectVectorsEqual(@ctz(x), expected);
}

test "const number literal" {
    const one = 1;
    const eleven = ten + one;

    try expect(eleven == 11);
}
const ten = 10;

test "float equality" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    const x: f64 = 0.012;
    const y: f64 = x + 1.0;

    try testFloatEqualityImpl(x, y);
    try comptime testFloatEqualityImpl(x, y);
}

fn testFloatEqualityImpl(x: f64, y: f64) !void {
    const y2 = x + 1.0;
    try expect(y == y2);
}

test "hex float literal parsing" {
    comptime assert(0x1.0 == 1.0);
}

test "hex float literal within range" {
    const a = 0x1.0p16383;
    const b = 0x0.1p16387;
    const c = 0x1.0p-16382;
    _ = a;
    _ = b;
    _ = c;
}

test "quad hex float literal parsing in range" {
    const a = 0x1.af23456789bbaaab347645365cdep+5;
    const b = 0x1.dedafcff354b6ae9758763545432p-9;
    const c = 0x1.2f34dd5f437e849b4baab754cdefp+4534;
    const d = 0x1.edcbff8ad76ab5bf46463233214fp-435;
    _ = a;
    _ = b;
    _ = c;
    _ = d;
}

test "underscore separator parsing" {
    try expect(1_234_567 == 1234567);
    try expect(1_234_567 == 1234567);
    try expect(1_2_3_4_5_6_7 == 1234567);

    try expect(0b0_0_0_0 == 0);
    try expect(0b1010_1010 == 0b10101010);
    try expect(0b0000_1010_1010 == 0b10101010);
    try expect(0b1_0_1_0_1_0_1_0 == 0b10101010);

    try expect(0o0_0_0_0 == 0);
    try expect(0o1010_1010 == 0o10101010);
    try expect(0o0000_1010_1010 == 0o10101010);
    try expect(0o1_0_1_0_1_0_1_0 == 0o10101010);

    try expect(0x0_0_0_0 == 0);
    try expect(0x1010_1010 == 0x10101010);
    try expect(0x0000_1010_1010 == 0x10101010);
    try expect(0x1_0_1_0_1_0_1_0 == 0x10101010);

    try expect(123_456.789_000e1_0 == 123456.789000e10);
    try expect(1_2_3_4_5_6.7_8_9_0_0_0e0_0_1_0 == 123456.789000e10);

    try expect(0x1234_5678.9ABC_DEF0p-1_0 == 0x12345678.9ABCDEF0p-10);
    try expect(0x1_2_3_4_5_6_7_8.9_A_B_C_D_E_F_0p-0_0_0_1_0 == 0x12345678.9ABCDEF0p-10);
}

test "comptime_int addition" {
    comptime {
        try expect(35361831660712422535336160538497375248 + 101752735581729509668353361206450473702 == 137114567242441932203689521744947848950);
        try expect(594491908217841670578297176641415611445982232488944558774612 + 390603545391089362063884922208143568023166603618446395589768 == 985095453608931032642182098849559179469148836107390954364380);
    }
}

test "comptime_int multiplication" {
    comptime {
        try expect(
            45960427431263824329884196484953148229 * 128339149605334697009938835852565949723 == 5898522172026096622534201617172456926982464453350084962781392314016180490567,
        );
        try expect(
            594491908217841670578297176641415611445982232488944558774612 * 390603545391089362063884922208143568023166603618446395589768 == 232210647056203049913662402532976186578842425262306016094292237500303028346593132411865381225871291702600263463125370016,
        );
    }
}

test "comptime_int shifting" {
    comptime {
        try expect((@as(u128, 1) << 127) == 0x80000000000000000000000000000000);
    }
}

test "comptime_int multi-limb shift and mask" {
    comptime {
        var a = 0xefffffffa0000001eeeeeeefaaaaaaab;

        try expect(@as(u32, a & 0xffffffff) == 0xaaaaaaab);
        a >>= 32;
        try expect(@as(u32, a & 0xffffffff) == 0xeeeeeeef);
        a >>= 32;
        try expect(@as(u32, a & 0xffffffff) == 0xa0000001);
        a >>= 32;
        try expect(@as(u32, a & 0xffffffff) == 0xefffffff);
        a >>= 32;

        try expect(a == 0);
    }
}

test "comptime_int multi-limb partial shift right" {
    comptime {
        var a = 0x1ffffffffeeeeeeee;
        a >>= 16;
        try expect(a == 0x1ffffffffeeee);
    }
}

test "xor" {
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try test_xor();
    try comptime test_xor();
}

fn test_xor() !void {
    try testOneXor(0xFF, 0x00, 0xFF);
    try testOneXor(0xF0, 0x0F, 0xFF);
    try testOneXor(0xFF, 0xF0, 0x0F);
    try testOneXor(0xFF, 0x0F, 0xF0);
    try testOneXor(0xFF, 0xFF, 0x00);
}

fn testOneXor(a: u8, b: u8, c: u8) !void {
    try expect(a ^ b == c);
}

test "comptime_int xor" {
    comptime {
        try expect(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ^ 0x00000000000000000000000000000000 == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        try expect(0xFFFFFFFFFFFFFFFF0000000000000000 ^ 0x0000000000000000FFFFFFFFFFFFFFFF == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        try expect(0xFFFFFFFFFFFFFFFF0000000000000000 ^ 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0x0000000000000000FFFFFFFFFFFFFFFF);
        try expect(0x0000000000000000FFFFFFFFFFFFFFFF ^ 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0xFFFFFFFFFFFFFFFF0000000000000000);
        try expect(0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF ^ 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0x00000000000000000000000000000000);
        try expect(0xFFFFFFFF00000000FFFFFFFF00000000 ^ 0x00000000FFFFFFFF00000000FFFFFFFF == 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
        try expect(0xFFFFFFFF00000000FFFFFFFF00000000 ^ 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0x00000000FFFFFFFF00000000FFFFFFFF);
        try expect(0x00000000FFFFFFFF00000000FFFFFFFF ^ 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF == 0xFFFFFFFF00000000FFFFFFFF00000000);
    }
}

test "comptime_int param and return" {
    const a = comptimeAdd(35361831660712422535336160538497375248, 101752735581729509668353361206450473702);
    try expect(a == 137114567242441932203689521744947848950);

    const b = comptimeAdd(594491908217841670578297176641415611445982232488944558774612, 390603545391089362063884922208143568023166603618446395589768);
    try expect(b == 985095453608931032642182098849559179469148836107390954364380);
}

fn comptimeAdd(comptime a: comptime_int, comptime b: comptime_int) comptime_int {
    return a + b;
}

fn not(comptime T: type, a: T) T {
    return ~a;
}

test "binary not" {
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try expect(not(u0, 0) == 0);
    try expect(not(u1, 0) == 1);
    try expect(not(u1, 1) == 0);
    try expect(not(u5, 0b01001) == 0b10110);
    try expect(not(u5, 0b10110) == 0b01001);
    try expect(not(u16, 0b10101010_10101010) == 0b01010101_01010101);
    try expect(not(u16, 0b01010101_01010101) == 0b10101010_10101010);
    try expect(not(u32, 0xAAAA_3333) == 0x5555_CCCC);
    try expect(not(u32, 0x5555_CCCC) == 0xAAAA_3333);
    try expect(not(u35, 0x4_1111_FFFF) == 0x3_EEEE_0000);
    try expect(not(u35, 0x3_EEEE_0000) == 0x4_1111_FFFF);
    try expect(not(u48, 0x4567_89AB_CDEF) == 0xBA98_7654_3210);
    try expect(not(u48, 0xBA98_7654_3210) == 0x4567_89AB_CDEF);
    try expect(not(u64, 0x0123_4567_89AB_CDEF) == 0xFEDC_BA98_7654_3210);
    try expect(not(u64, 0xFEDC_BA98_7654_3210) == 0x0123_4567_89AB_CDEF);

    try expect(not(i0, 0) == 0);
    try expect(not(i1, 0) == -1);
    try expect(not(i1, -1) == 0);
    try expect(not(i5, -2) == 1);
    try expect(not(i5, 3) == -4);
    try expect(not(i32, 0) == -1);
    try expect(not(i32, -2147483648) == 2147483647);
    try expect(not(i64, -1) == 0);
    try expect(not(i64, 0) == -1);

    try expect(comptime x: {
        break :x ~@as(u16, 0b1010101010101010) == 0b0101010101010101;
    });
    try expect(comptime x: {
        break :x ~@as(u64, 2147483647) == 18446744071562067968;
    });
    try expect(comptime x: {
        break :x ~@as(u0, 0) == 0;
    });
}

test "binary not big int <= 128 bits" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try expect(not(u65, 1) == 0x1_FFFFFFFF_FFFFFFFE);
    try expect(not(u65, 0x1_FFFFFFFF_FFFFFFFE) == 1);

    try expect(not(u96, 0x01234567_89ABCDEF_00000001) == 0xFEDCBA98_76543210_FFFFFFFE);
    try expect(not(u96, 0xFEDCBA98_76543210_FFFFFFFE) == 0x01234567_89ABCDEF_00000001);

    try expect(not(u128, 0xAAAAAAAA_AAAAAAAA_AAAAAAAA_AAAAAAAA) == 0x55555555_55555555_55555555_55555555);
    try expect(not(u128, 0x55555555_55555555_55555555_55555555) == 0xAAAAAAAA_AAAAAAAA_AAAAAAAA_AAAAAAAA);

    try expect(not(i65, -1) == 0);
    try expect(not(i65, 0) == -1);
    try expect(not(i65, -18446744073709551616) == 18446744073709551615);
    try expect(not(i65, 18446744073709551615) == -18446744073709551616);

    try expect(not(i128, -1) == 0);
    try expect(not(i128, 0) == -1);
    try expect(not(i128, -200) == 199);
    try expect(not(i128, 199) == -200);

    try expect(comptime x: {
        break :x ~@as(u128, 0x55555555_55555555_55555555_55555555) == 0xaaaaaaaa_aaaaaaaa_aaaaaaaa_aaaaaaaa;
    });
    try expect(comptime x: {
        break :x ~@as(i128, 0x55555555_55555555_55555555_55555555) == @as(i128, @bitCast(@as(u128, 0xaaaaaaaa_aaaaaaaa_aaaaaaaa_aaaaaaaa)));
    });
}

test "division" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testIntDivision();
    try comptime testIntDivision();

    try testFloatDivision();
    try comptime testFloatDivision();
}

fn testIntDivision() !void {
    try expect(div(u32, 13, 3) == 4);
    try expect(div(u64, 13, 3) == 4);
    try expect(div(u8, 13, 3) == 4);

    try expect(divExact(u32, 55, 11) == 5);
    try expect(divExact(i32, -55, 11) == -5);
    try expect(divExact(i64, -55, 11) == -5);
    try expect(divExact(i16, -55, 11) == -5);

    try expect(divFloor(i32, 5, 3) == 1);
    try expect(divFloor(i32, -5, 3) == -2);
    try expect(divFloor(i32, -0x80000000, -2) == 0x40000000);
    try expect(divFloor(i32, 0, -0x80000000) == 0);
    try expect(divFloor(i32, -0x40000001, 0x40000000) == -2);
    try expect(divFloor(i32, -0x80000000, 1) == -0x80000000);
    try expect(divFloor(i32, 10, 12) == 0);
    try expect(divFloor(i32, -14, 12) == -2);
    try expect(divFloor(i32, -2, 12) == -1);

    try expect(divFloor(i8, 5, 3) == 1);
    try expect(divFloor(i16, -5, 3) == -2);
    try expect(divFloor(i64, -0x80000000, -2) == 0x40000000);
    try expect(divFloor(i64, -0x40000001, 0x40000000) == -2);

    try expect(divTrunc(i32, 5, 3) == 1);
    try expect(divTrunc(i32, -5, 3) == -1);
    try expect(divTrunc(i32, 9, -10) == 0);
    try expect(divTrunc(i32, -9, 10) == 0);
    try expect(divTrunc(i32, 10, 12) == 0);
    try expect(divTrunc(i32, -14, 12) == -1);
    try expect(divTrunc(i32, -2, 12) == 0);

    try expect(mod(i32, 10, 12) == 10);
    try expect(mod(i32, -14, 12) == 10);
    try expect(mod(i32, -2, 12) == 10);
    try expect(mod(i32, 10, -12) == -2);
    try expect(mod(i32, -14, -12) == -2);
    try expect(mod(i32, -2, -12) == -2);

    try expect(mod(i64, -118, 12) == 2);
    try expect(mod(u32, 10, 12) == 10);
    try expect(mod(i64, -14, 12) == 10);
    try expect(mod(i16, -2, 12) == 10);
    try expect(mod(i16, -118, 12) == 2);
    try expect(mod(i8, -2, 12) == 10);

    try expect(rem(i64, -118, 12) == -10);
    try expect(rem(i32, 10, 12) == 10);
    try expect(rem(i32, -14, 12) == -2);
    try expect(rem(i32, -2, 12) == -2);
    try expect(rem(i16, -118, 12) == -10);

    try expect(divTrunc(i20, 20, -5) == -4);
    try expect(divTrunc(i20, -20, -4) == 5);

    comptime {
        try expect(
            1194735857077236777412821811143690633098347576 % 508740759824825164163191790951174292733114988 == 177254337427586449086438229241342047632117600,
        );
        try expect(
            @rem(-1194735857077236777412821811143690633098347576, 508740759824825164163191790951174292733114988) == -177254337427586449086438229241342047632117600,
        );
        try expect(
            1194735857077236777412821811143690633098347576 / 508740759824825164163191790951174292733114988 == 2,
        );
        try expect(
            @divTrunc(-1194735857077236777412821811143690633098347576, 508740759824825164163191790951174292733114988) == -2,
        );
        try expect(
            @divTrunc(1194735857077236777412821811143690633098347576, -508740759824825164163191790951174292733114988) == -2,
        );
        try expect(
            @divTrunc(-1194735857077236777412821811143690633098347576, -508740759824825164163191790951174292733114988) == 2,
        );
        try expect(
            4126227191251978491697987544882340798050766755606969681711 % 10 == 1,
        );
    }
}

fn testFloatDivision() !void {
    try expect(div(f32, 1.0, 2.0) == 0.5);

    try expect(divExact(f32, 55.0, 11.0) == 5.0);
    try expect(divExact(f32, -55.0, 11.0) == -5.0);

    try expect(divFloor(f32, 5.0, 3.0) == 1.0);
    try expect(divFloor(f32, -5.0, 3.0) == -2.0);
    try expect(divFloor(f32, 56.0, 9.0) == 6.0);
    try expect(divFloor(f32, 1053.0, -41.0) == -26.0);
    try expect(divFloor(f16, -43.0, 12.0) == -4.0);
    try expect(divFloor(f64, -90.0, -9.0) == 10.0);

    try expect(divTrunc(f32, 5.0, 3.0) == 1.0);
    try expect(divTrunc(f32, -5.0, 3.0) == -1.0);
    try expect(divTrunc(f32, 9.0, -10.0) == 0.0);
    try expect(divTrunc(f32, -9.0, 10.0) == 0.0);
    try expect(divTrunc(f64, 5.0, 3.0) == 1.0);
    try expect(divTrunc(f64, -5.0, 3.0) == -1.0);
    try expect(divTrunc(f64, 9.0, -10.0) == 0.0);
    try expect(divTrunc(f64, -9.0, 10.0) == 0.0);
}

test "large integer division" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    {
        var numerator: u256 = 99999999999999999997315645440;
        var divisor: u256 = 10000000000000000000000000000;
        _ = .{ &numerator, &divisor };
        try expect(numerator / divisor == 9);
    }
    {
        var numerator: u256 = 99999999999999999999000000000000000000000;
        var divisor: u256 = 10000000000000000000000000000000000000000;
        _ = .{ &numerator, &divisor };
        try expect(numerator / divisor == 9);
    }
}

test "division half-precision floats" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testDivisionFP16();
    try comptime testDivisionFP16();
}

fn testDivisionFP16() !void {
    try expect(div(f16, 1.0, 2.0) == 0.5);

    try expect(divExact(f16, 55.0, 11.0) == 5.0);
    try expect(divExact(f16, -55.0, 11.0) == -5.0);

    try expect(divFloor(f16, 5.0, 3.0) == 1.0);
    try expect(divFloor(f16, -5.0, 3.0) == -2.0);
    try expect(divTrunc(f16, 5.0, 3.0) == 1.0);
    try expect(divTrunc(f16, -5.0, 3.0) == -1.0);
    try expect(divTrunc(f16, 9.0, -10.0) == 0.0);
    try expect(divTrunc(f16, -9.0, 10.0) == 0.0);
}

fn div(comptime T: type, a: T, b: T) T {
    return a / b;
}
fn divExact(comptime T: type, a: T, b: T) T {
    return @divExact(a, b);
}
fn divFloor(comptime T: type, a: T, b: T) T {
    return @divFloor(a, b);
}
fn divTrunc(comptime T: type, a: T, b: T) T {
    return @divTrunc(a, b);
}
fn mod(comptime T: type, a: T, b: T) T {
    return @mod(a, b);
}
fn rem(comptime T: type, a: T, b: T) T {
    return @rem(a, b);
}

test "unsigned wrapping" {
    try testUnsignedWrappingEval(maxInt(u32));
    try comptime testUnsignedWrappingEval(maxInt(u32));
}
fn testUnsignedWrappingEval(x: u32) !void {
    const zero = x +% 1;
    try expect(zero == 0);
    const orig = zero -% 1;
    try expect(orig == maxInt(u32));
}

test "signed wrapping" {
    try testSignedWrappingEval(maxInt(i32));
    try comptime testSignedWrappingEval(maxInt(i32));
}
fn testSignedWrappingEval(x: i32) !void {
    const min_val = x +% 1;
    try expect(min_val == minInt(i32));
    const max_val = min_val -% 1;
    try expect(max_val == maxInt(i32));
}

test "signed negation wrapping" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testSignedNegationWrappingEval(minInt(i16));
    try comptime testSignedNegationWrappingEval(minInt(i16));
}
fn testSignedNegationWrappingEval(x: i16) !void {
    try expect(x == -32768);
    const neg = -%x;
    try expect(neg == -32768);
}

test "unsigned negation wrapping" {
    try testUnsignedNegationWrappingEval(1);
    try comptime testUnsignedNegationWrappingEval(1);
}
fn testUnsignedNegationWrappingEval(x: u16) !void {
    try expect(x == 1);
    const neg = -%x;
    try expect(neg == maxInt(u16));
}

test "negation wrapping" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try expectEqual(@as(u1, 1), negateWrap(u1, 1));
}

fn negateWrap(comptime T: type, x: T) T {
    // This is specifically testing a safety-checked add, so
    // special case minInt(T) which would overflow otherwise.
    return if (x == minInt(T)) minInt(T) else ~x + 1;
}

test "unsigned 64-bit division" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    try test_u64_div();
    try comptime test_u64_div();
}
fn test_u64_div() !void {
    const result = divWithResult(1152921504606846976, 34359738365);
    try expect(result.quotient == 33554432);
    try expect(result.remainder == 100663296);
}
fn divWithResult(a: u64, b: u64) DivResult {
    return DivResult{
        .quotient = a / b,
        .remainder = a % b,
    };
}
const DivResult = struct {
    quotient: u64,
    remainder: u64,
};

test "bit shift a u1" {
    var x: u1 = 1;
    _ = &x;
    const y = x << 0;
    try expect(y == 1);
}

test "truncating shift right" {
    try testShrTrunc(maxInt(u16));
    try comptime testShrTrunc(maxInt(u16));
}
fn testShrTrunc(x: u16) !void {
    const shifted = x >> 1;
    try expect(shifted == 32767);
}

test "f128" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try test_f128();
    try comptime test_f128();
}

fn make_f128(x: f128) f128 {
    return x;
}

fn test_f128() !void {
    try expect(@sizeOf(f128) == 16);
    try expect(make_f128(1.0) == 1.0);
    try expect(make_f128(1.0) != 1.1);
    try expect(make_f128(1.0) > 0.9);
    try expect(make_f128(1.0) >= 0.9);
    try expect(make_f128(1.0) >= 1.0);
    try should_not_be_zero(1.0);
}

fn should_not_be_zero(x: f128) !void {
    try expect(x != 0.0);
}

test "umax wrapped squaring" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    {
        var x: u4 = maxInt(u4);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u8 = maxInt(u8);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u12 = maxInt(u12);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u16 = maxInt(u16);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u24 = maxInt(u24);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u32 = maxInt(u32);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u48 = maxInt(u48);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u64 = maxInt(u64);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u96 = maxInt(u96);
        x *%= x;
        try expect(x == 1);
    }
    {
        var x: u128 = maxInt(u128);
        x *%= x;
        try expect(x == 1);
    }
}

test "128-bit multiplication" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    {
        var a: i128 = 3;
        var b: i128 = 2;
        var c = a * b;
        try expect(c == 6);

        a = -3;
        b = 2;
        c = a * b;
        try expect(c == -6);
    }

    {
        var a: u128 = 0xffffffffffffffff;
        var b: u128 = 100;
        _ = .{ &a, &b };
        const c = a * b;
        try expect(c == 0x63ffffffffffffff9c);
    }
}

fn testAddWithOverflow(comptime T: type, a: T, b: T, add: T, bit: u1) !void {
    const ov = @addWithOverflow(a, b);
    try expect(ov[0] == add);
    try expect(ov[1] == bit);
}

test "@addWithOverflow" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    try testAddWithOverflow(u8, 250, 100, 94, 1);
    try testAddWithOverflow(u8, 100, 150, 250, 0);

    try testAddWithOverflow(u8, 200, 99, 43, 1);
    try testAddWithOverflow(u8, 200, 55, 255, 0);

    try testAddWithOverflow(usize, 6, 6, 12, 0);
    try testAddWithOverflow(usize, maxInt(usize), 6, 5, 1);

    try testAddWithOverflow(isize, -6, -6, -12, 0);
    try testAddWithOverflow(isize, minInt(isize), -6, maxInt(isize) - 5, 1);
}

test "@addWithOverflow > 64 bits" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    try testAddWithOverflow(u65, 4, 105, 109, 0);
    try testAddWithOverflow(u65, 1000, 100, 1100, 0);
    try testAddWithOverflow(u65, 100, maxInt(u65) - 99, 0, 1);
    try testAddWithOverflow(u65, maxInt(u65), maxInt(u65), maxInt(u65) - 1, 1);
    try testAddWithOverflow(u65, maxInt(u65) - 1, maxInt(u65), maxInt(u65) - 2, 1);
    try testAddWithOverflow(u65, maxInt(u65), maxInt(u65) - 1, maxInt(u65) - 2, 1);

    try testAddWithOverflow(u128, 4, 105, 109, 0);
    try testAddWithOverflow(u128, 1000, 100, 1100, 0);
    try testAddWithOverflow(u128, 100, maxInt(u128) - 99, 0, 1);
    try testAddWithOverflow(u128, maxInt(u128), maxInt(u128), maxInt(u128) - 1, 1);
    try testAddWithOverflow(u128, maxInt(u128) - 1, maxInt(u128), maxInt(u128) - 2, 1);
    try testAddWithOverflow(u128, maxInt(u128), maxInt(u128) - 1, maxInt(u128) - 2, 1);

    try testAddWithOverflow(i65, 4, -105, -101, 0);
    try testAddWithOverflow(i65, 1000, 100, 1100, 0);
    try testAddWithOverflow(i65, minInt(i65), 1, minInt(i65) + 1, 0);
    try testAddWithOverflow(i65, maxInt(i65), minInt(i65), -1, 0);
    try testAddWithOverflow(i65, minInt(i65), maxInt(i65), -1, 0);
    try testAddWithOverflow(i65, maxInt(i65), -2, maxInt(i65) - 2, 0);
    try testAddWithOverflow(i65, maxInt(i65), maxInt(i65), -2, 1);
    try testAddWithOverflow(i65, minInt(i65), minInt(i65), 0, 1);
    try testAddWithOverflow(i65, maxInt(i65) - 1, maxInt(i65), -3, 1);
    try testAddWithOverflow(i65, maxInt(i65), maxInt(i65) - 1, -3, 1);

    try testAddWithOverflow(i128, 4, -105, -101, 0);
    try testAddWithOverflow(i128, 1000, 100, 1100, 0);
    try testAddWithOverflow(i128, minInt(i128), 1, minInt(i128) + 1, 0);
    try testAddWithOverflow(i128, maxInt(i128), minInt(i128), -1, 0);
    try testAddWithOverflow(i128, minInt(i128), maxInt(i128), -1, 0);
    try testAddWithOverflow(i128, maxInt(i128), -2, maxInt(i128) - 2, 0);
    try testAddWithOverflow(i128, maxInt(i128), maxInt(i128), -2, 1);
    try testAddWithOverflow(i128, minInt(i128), minInt(i128), 0, 1);
    try testAddWithOverflow(i128, maxInt(i128) - 1, maxInt(i128), -3, 1);
    try testAddWithOverflow(i128, maxInt(i128), maxInt(i128) - 1, -3, 1);
}

test "small int addition" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    var x: u2 = 0;
    try expect(x == 0);

    x += 1;
    try expect(x == 1);

    x += 1;
    try expect(x == 2);

    x += 1;
    try expect(x == 3);

    const ov = @addWithOverflow(x, 1);
    try expect(ov[0] == 0);
    try expect(ov[1] == 1);
}

fn testMulWithOverflow(comptime T: type, a: T, b: T, mul: T, bit: u1) !void {
    const ov = @mulWithOverflow(a, b);
    try expect(ov[0] == mul);
    try expect(ov[1] == bit);
}

test "basic @mulWithOverflow" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest; // TODO

    try testMulWithOverflow(u8, 86, 3, 2, 1);
    try testMulWithOverflow(u8, 85, 3, 255, 0);

    try testMulWithOverflow(u8, 123, 2, 246, 0);
    try testMulWithOverflow(u8, 123, 4, 236, 1);
}

test "extensive @mulWithOverflow" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    try testMulWithOverflow(u5, 3, 10, 30, 0);
    try testMulWithOverflow(u5, 3, 11, 1, 1);
    try testMulWithOverflow(i5, 3, -5, -15, 0);
    try testMulWithOverflow(i5, 3, -6, 14, 1);

    try testMulWithOverflow(u8, 3, 85, 255, 0);
    try testMulWithOverflow(u8, 3, 86, 2, 1);
    try testMulWithOverflow(i8, 3, -42, -126, 0);
    try testMulWithOverflow(i8, 3, -43, 127, 1);

    try testMulWithOverflow(u14, 3, 0x1555, 0x3fff, 0);
    try testMulWithOverflow(u14, 3, 0x1556, 2, 1);
    try testMulWithOverflow(i14, 3, -0xaaa, -0x1ffe, 0);
    try testMulWithOverflow(i14, 3, -0xaab, 0x1fff, 1);

    try testMulWithOverflow(u16, 3, 0x5555, 0xffff, 0);
    try testMulWithOverflow(u16, 3, 0x5556, 2, 1);
    try testMulWithOverflow(i16, 3, -0x2aaa, -0x7ffe, 0);
    try testMulWithOverflow(i16, 3, -0x2aab, 0x7fff, 1);

    try testMulWithOverflow(u30, 3, 0x15555555, 0x3fffffff, 0);
    try testMulWithOverflow(u30, 3, 0x15555556, 2, 1);
    try testMulWithOverflow(i30, 3, -0xaaaaaaa, -0x1ffffffe, 0);
    try testMulWithOverflow(i30, 3, -0xaaaaaab, 0x1fffffff, 1);

    try testMulWithOverflow(u32, 3, 0x55555555, 0xffffffff, 0);
    try testMulWithOverflow(u32, 3, 0x55555556, 2, 1);
    try testMulWithOverflow(i32, 3, -0x2aaaaaaa, -0x7ffffffe, 0);
    try testMulWithOverflow(i32, 3, -0x2aaaaaab, 0x7fffffff, 1);

    try testMulWithOverflow(u31, 1 << 30, 1 << 30, 0, 1);
    try testMulWithOverflow(i31, minInt(i31), minInt(i31), 0, 1);
}

test "@mulWithOverflow bitsize > 32" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    try testMulWithOverflow(u40, 3, 0x55_5555_5555, 0xff_ffff_ffff, 0);
    try testMulWithOverflow(u40, 3, 0x55_5555_5556, 2, 1);
    try testMulWithOverflow(u40, 0x10_0000_0000, 0x10_0000_0000, 0, 1);

    try testMulWithOverflow(i40, 3, -0x2a_aaaa_aaaa, -0x7f_ffff_fffe, 0);
    try testMulWithOverflow(i40, 3, -0x2a_aaaa_aaab, 0x7f_ffff_ffff, 1);
    try testMulWithOverflow(i40, 6, -0x2a_aaaa_aaab, -2, 1);
    try testMulWithOverflow(i40, 0x08_0000_0000, -0x08_0000_0001, -0x8_0000_0000, 1);

    try testMulWithOverflow(u62, 3, 0x1555555555555555, 0x3fffffffffffffff, 0);
    try testMulWithOverflow(u62, 3, 0x1555555555555556, 2, 1);
    try testMulWithOverflow(i62, 3, -0xaaaaaaaaaaaaaaa, -0x1ffffffffffffffe, 0);
    try testMulWithOverflow(i62, 3, -0xaaaaaaaaaaaaaab, 0x1fffffffffffffff, 1);

    try testMulWithOverflow(u64, 3, 0x5555555555555555, 0xffffffffffffffff, 0);
    try testMulWithOverflow(u64, 3, 0x5555555555555556, 2, 1);
    try testMulWithOverflow(i64, 3, -0x2aaaaaaaaaaaaaaa, -0x7ffffffffffffffe, 0);
    try testMulWithOverflow(i64, 3, -0x2aaaaaaaaaaaaaab, 0x7fffffffffffffff, 1);

    try testMulWithOverflow(u63, 1 << 62, 1 << 62, 0, 1);
    try testMulWithOverflow(i63, minInt(i63), minInt(i63), 0, 1);
}

test "@mulWithOverflow bitsize 128 bits" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    try testMulWithOverflow(u128, 3, 0x5555555555555555_5555555555555555, 0xffffffffffffffff_ffffffffffffffff, 0);
    try testMulWithOverflow(u128, 3, 0x5555555555555555_5555555555555556, 2, 1);

    try testMulWithOverflow(u128, 1 << 100, 1 << 27, 1 << 127, 0);
    try testMulWithOverflow(u128, maxInt(u128), maxInt(u128), 1, 1);
    try testMulWithOverflow(u128, 1 << 100, 1 << 28, 0, 1);
    try testMulWithOverflow(u128, 1 << 127, 1 << 127, 0, 1);

    try testMulWithOverflow(i128, 3, -0x2aaaaaaaaaaaaaaa_aaaaaaaaaaaaaaaa, -0x7fffffffffffffff_fffffffffffffffe, 0);
    try testMulWithOverflow(i128, 3, -0x2aaaaaaaaaaaaaaa_aaaaaaaaaaaaaaab, 0x7fffffffffffffff_ffffffffffffffff, 1);
    try testMulWithOverflow(i128, -1, -1, 1, 0);
    try testMulWithOverflow(i128, minInt(i128), minInt(i128), 0, 1);

    try testMulWithOverflow(i128, 1 << 126, 1 << 1, -1 << 127, 1);
    try testMulWithOverflow(i128, -1 << 105, 1 << 22, -1 << 127, 0);
    try testMulWithOverflow(i128, 1 << 84, -1 << 43, -1 << 127, 0);
    try testMulWithOverflow(i128, -1 << 63, -1 << 64, -1 << 127, 1);
}

test "@mulWithOverflow bitsize 256 bits" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    {
        const const_lhs: u256 = 8035709466408580321693645878924206181189;
        const const_rhs: u256 = 343954217539185679456797259115612849079;
        const const_result = @mulWithOverflow(const_lhs, const_rhs);
        comptime assert(const_result[0] == 100698109432518020450541558444080472799095368135495022414802684874680804056403);
        comptime assert(const_result[1] == 1);

        var var_lhs = const_lhs;
        var var_rhs = const_rhs;
        _ = .{ &var_lhs, &var_rhs };
        const var_result = @mulWithOverflow(var_lhs, var_rhs);
        try std.testing.expect(var_result[0] == const_result[0]);
        try std.testing.expect(var_result[1] == const_result[1]);
    }
    {
        const const_lhs: u256 = 100477140835310762407466294984162740292250605075409128262608;
        const const_rhs: u256 = 406310585934439581231;
        const const_result = @mulWithOverflow(const_lhs, const_rhs);
        comptime assert(const_result[0] == 66110554277021146912650321519727251744526528332039438002889524600764482652976);
        comptime assert(const_result[1] == 1);

        var var_lhs = const_lhs;
        var var_rhs = const_rhs;
        _ = .{ &var_lhs, &var_rhs };
        const var_result = @mulWithOverflow(var_lhs, var_rhs);
        try std.testing.expect(var_result[0] == const_result[0]);
        try std.testing.expect(var_result[1] == const_result[1]);
    }
    try testMulWithOverflow(i256, 1 << 254, 1 << 1, -1 << 255, 1);
    try testMulWithOverflow(i256, -1 << 212, 1 << 43, -1 << 255, 0);
    try testMulWithOverflow(i256, 1 << 170, -1 << 85, -1 << 255, 0);
    try testMulWithOverflow(i256, -1 << 128, -1 << 127, -1 << 255, 1);
}

fn testSubWithOverflow(comptime T: type, a: T, b: T, sub: T, bit: u1) !void {
    const ov = @subWithOverflow(a, b);
    try expect(ov[0] == sub);
    try expect(ov[1] == bit);
}

test "@subWithOverflow" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    try testSubWithOverflow(u8, 1, 2, 255, 1);
    try testSubWithOverflow(u8, 1, 1, 0, 0);

    try testSubWithOverflow(u16, 10000, 10002, 65534, 1);
    try testSubWithOverflow(u16, 10000, 9999, 1, 0);

    try testSubWithOverflow(usize, 6, 6, 0, 0);
    try testSubWithOverflow(usize, 6, 7, maxInt(usize), 1);
    try testSubWithOverflow(isize, -6, -6, 0, 0);
    try testSubWithOverflow(isize, minInt(isize), 6, maxInt(isize) - 5, 1);
}

test "@subWithOverflow > 64 bits" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest; // TODO

    try testSubWithOverflow(u65, 4, 105, maxInt(u65) - 100, 1);
    try testSubWithOverflow(u65, 1000, 100, 900, 0);
    try testSubWithOverflow(u65, maxInt(u65), maxInt(u65), 0, 0);
    try testSubWithOverflow(u65, maxInt(u65) - 1, maxInt(u65), maxInt(u65), 1);
    try testSubWithOverflow(u65, maxInt(u65), maxInt(u65) - 1, 1, 0);

    try testSubWithOverflow(u128, 4, 105, maxInt(u128) - 100, 1);
    try testSubWithOverflow(u128, 1000, 100, 900, 0);
    try testSubWithOverflow(u128, maxInt(u128), maxInt(u128), 0, 0);
    try testSubWithOverflow(u128, maxInt(u128) - 1, maxInt(u128), maxInt(u128), 1);
    try testSubWithOverflow(u128, maxInt(u128), maxInt(u128) - 1, 1, 0);

    try testSubWithOverflow(i65, 4, 105, -101, 0);
    try testSubWithOverflow(i65, 1000, 100, 900, 0);
    try testSubWithOverflow(i65, maxInt(i65), maxInt(i65), 0, 0);
    try testSubWithOverflow(i65, minInt(i65), minInt(i65), 0, 0);
    try testSubWithOverflow(i65, maxInt(i65) - 1, maxInt(i65), -1, 0);
    try testSubWithOverflow(i65, maxInt(i65), maxInt(i65) - 1, 1, 0);
    try testSubWithOverflow(i65, minInt(i65), 1, maxInt(i65), 1);
    try testSubWithOverflow(i65, maxInt(i65), minInt(i65), -1, 1);
    try testSubWithOverflow(i65, minInt(i65), maxInt(i65), 1, 1);
    try testSubWithOverflow(i65, maxInt(i65), -2, minInt(i65) + 1, 1);

    try testSubWithOverflow(i128, 4, 105, -101, 0);
    try testSubWithOverflow(i128, 1000, 100, 900, 0);
    try testSubWithOverflow(i128, maxInt(i128), maxInt(i128), 0, 0);
    try testSubWithOverflow(i128, minInt(i128), minInt(i128), 0, 0);
    try testSubWithOverflow(i128, maxInt(i128) - 1, maxInt(i128), -1, 0);
    try testSubWithOverflow(i128, maxInt(i128), maxInt(i128) - 1, 1, 0);
    try testSubWithOverflow(i128, minInt(i128), 1, maxInt(i128), 1);
    try testSubWithOverflow(i128, maxInt(i128), minInt(i128), -1, 1);
    try testSubWithOverflow(i128, minInt(i128), maxInt(i128), 1, 1);
    try testSubWithOverflow(i128, maxInt(i128), -2, minInt(i128) + 1, 1);
}

fn testShlWithOverflow(comptime T: type, a: T, b: math.Log2Int(T), shl: T, bit: u1) !void {
    const ov = @shlWithOverflow(a, b);
    try expect(ov[0] == shl);
    try expect(ov[1] == bit);
}

test "@shlWithOverflow" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testShlWithOverflow(u4, 2, 1, 4, 0);
    try testShlWithOverflow(u4, 2, 3, 0, 1);

    try testShlWithOverflow(i9, 127, 1, 254, 0);
    try testShlWithOverflow(i9, 127, 2, -4, 1);

    try testShlWithOverflow(u16, 0b0010111111111111, 3, 0b0111111111111000, 1);
    try testShlWithOverflow(u16, 0b0010111111111111, 2, 0b1011111111111100, 0);

    try testShlWithOverflow(u16, 0b0000_0000_0000_0011, 15, 0b1000_0000_0000_0000, 1);
    try testShlWithOverflow(u16, 0b0000_0000_0000_0011, 14, 0b1100_0000_0000_0000, 0);
}

test "@shlWithOverflow > 64 bits" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testShlWithOverflow(u65, 0x0_0100_0000_0000_0000, 7, 0x0_8000_0000_0000_0000, 0);
    try testShlWithOverflow(u65, 0x0_0100_0000_0000_0000, 8, 0x1_0000_0000_0000_0000, 0);
    try testShlWithOverflow(u65, 0x0_0100_0000_0000_0000, 9, 0, 1);
    try testShlWithOverflow(u65, 0x0_0100_0000_0000_0000, 10, 0, 1);

    try testShlWithOverflow(u128, 0x0100_0000_0000_0000_0000000000000000, 6, 0x4000_0000_0000_0000_0000000000000000, 0);
    try testShlWithOverflow(u128, 0x0100_0000_0000_0000_0000000000000000, 7, 0x8000_0000_0000_0000_0000000000000000, 0);
    try testShlWithOverflow(u128, 0x0100_0000_0000_0000_0000000000000000, 8, 0, 1);
    try testShlWithOverflow(u128, 0x0100_0000_0000_0000_0000000000000000, 9, 0, 1);

    try testShlWithOverflow(i65, 0x0_0100_0000_0000_0000, 7, 0x0_8000_0000_0000_0000, 0);
    try testShlWithOverflow(i65, 0x0_0100_0000_0000_0000, 8, minInt(i65), 1);
    try testShlWithOverflow(i65, 0x0_0100_0000_0000_0000, 9, 0, 1);
    try testShlWithOverflow(i65, 0x0_0100_0000_0000_0000, 10, 0, 1);

    try testShlWithOverflow(i128, 0x0100_0000_0000_0000_0000000000000000, 6, 0x4000_0000_0000_0000_0000000000000000, 0);
    try testShlWithOverflow(i128, 0x0100_0000_0000_0000_0000000000000000, 7, minInt(i128), 1);
    try testShlWithOverflow(i128, 0x0100_0000_0000_0000_0000000000000000, 8, 0, 1);
    try testShlWithOverflow(i128, 0x0100_0000_0000_0000_0000000000000000, 9, 0, 1);
}

test "overflow arithmetic with u0 values" {
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    {
        var a: u0 = 0;
        _ = &a;
        const ov = @addWithOverflow(a, 0);
        try expect(ov[1] == 0);
        try expect(ov[1] == 0);
    }
    {
        var a: u0 = 0;
        _ = &a;
        const ov = @subWithOverflow(a, 0);
        try expect(ov[1] == 0);
        try expect(ov[1] == 0);
    }
    {
        var a: u0 = 0;
        _ = &a;
        const ov = @mulWithOverflow(a, 0);
        try expect(ov[1] == 0);
        try expect(ov[1] == 0);
    }
    {
        var a: u0 = 0;
        _ = &a;
        const ov = @shlWithOverflow(a, 0);
        try expect(ov[1] == 0);
        try expect(ov[1] == 0);
    }
}

test "allow signed integer division/remainder when values are comptime-known and positive or exact" {
    try expect(5 / 3 == 1);
    try expect(-5 / -3 == 1);
    try expect(-6 / 3 == -2);

    try expect(5 % 3 == 2);
    try expect(-6 % 3 == 0);
}

test "quad hex float literal parsing accurate" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    const a: f128 = 0x1.1111222233334444555566667777p+0;

    // implied 1 is dropped, with an exponent of 0 (0x3fff) after biasing.
    const expected: u128 = 0x3fff1111222233334444555566667777;
    try expect(@as(u128, @bitCast(a)) == expected);

    // non-normalized
    const b: f128 = 0x11.111222233334444555566667777p-4;
    try expect(@as(u128, @bitCast(b)) == expected);

    const S = struct {
        fn doTheTest() !void {
            {
                var f: f128 = 0x1.2eab345678439abcdefea56782346p+5;
                _ = &f;
                try expect(@as(u128, @bitCast(f)) == 0x40042eab345678439abcdefea5678234);
            }
            {
                var f: f128 = 0x1.edcb34a235253948765432134674fp-1;
                _ = &f;
                try expect(@as(u128, @bitCast(f)) == 0x3ffeedcb34a235253948765432134675); // round-to-even
            }
            {
                var f: f128 = 0x1.353e45674d89abacc3a2ebf3ff4ffp-50;
                _ = &f;
                try expect(@as(u128, @bitCast(f)) == 0x3fcd353e45674d89abacc3a2ebf3ff50);
            }
            {
                var f: f128 = 0x1.ed8764648369535adf4be3214567fp-9;
                _ = &f;
                try expect(@as(u128, @bitCast(f)) == 0x3ff6ed8764648369535adf4be3214568);
            }
            const exp2ft = [_]f64{
                0x1.6a09e667f3bcdp-1,
                0x1.7a11473eb0187p-1,
                0x1.8ace5422aa0dbp-1,
                0x1.9c49182a3f090p-1,
                0x1.ae89f995ad3adp-1,
                0x1.c199bdd85529cp-1,
                0x1.d5818dcfba487p-1,
                0x1.ea4afa2a490dap-1,
                0x1.0000000000000p+0,
                0x1.0b5586cf9890fp+0,
                0x1.172b83c7d517bp+0,
                0x1.2387a6e756238p+0,
                0x1.306fe0a31b715p+0,
                0x1.3dea64c123422p+0,
                0x1.4bfdad5362a27p+0,
                0x1.5ab07dd485429p+0,
                0x1.8p23,
                0x1.62e430p-1,
                0x1.ebfbe0p-3,
                0x1.c6b348p-5,
                0x1.3b2c9cp-7,
                0x1.0p127,
                -0x1.0p-149,
            };

            const answers = [_]u64{
                0x3fe6a09e667f3bcd,
                0x3fe7a11473eb0187,
                0x3fe8ace5422aa0db,
                0x3fe9c49182a3f090,
                0x3feae89f995ad3ad,
                0x3fec199bdd85529c,
                0x3fed5818dcfba487,
                0x3feea4afa2a490da,
                0x3ff0000000000000,
                0x3ff0b5586cf9890f,
                0x3ff172b83c7d517b,
                0x3ff2387a6e756238,
                0x3ff306fe0a31b715,
                0x3ff3dea64c123422,
                0x3ff4bfdad5362a27,
                0x3ff5ab07dd485429,
                0x4168000000000000,
                0x3fe62e4300000000,
                0x3fcebfbe00000000,
                0x3fac6b3480000000,
                0x3f83b2c9c0000000,
                0x47e0000000000000,
                0xb6a0000000000000,
            };

            for (exp2ft, 0..) |x, i| {
                try expect(@as(u64, @bitCast(x)) == answers[i]);
            }
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "truncating shift left" {
    try testShlTrunc(maxInt(u16));
    try comptime testShlTrunc(maxInt(u16));
}
fn testShlTrunc(x: u16) !void {
    const shifted = x << 1;
    try expect(shifted == 65534);
}

test "exact shift left" {
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testShlExact(0b00110101);
    try comptime testShlExact(0b00110101);

    if (@shlExact(1, 1) != 2) @compileError("should be 2");
}
fn testShlExact(x: u8) !void {
    const shifted = @shlExact(x, 2);
    try expect(shifted == 0b11010100);
}

test "exact shift right" {
    try testShrExact(0b10110100);
    try comptime testShrExact(0b10110100);
}
fn testShrExact(x: u8) !void {
    const shifted = @shrExact(x, 2);
    try expect(shifted == 0b00101101);
}

test "shift left/right on u0 operand" {
    const S = struct {
        fn doTheTest() !void {
            var x: u0 = 0;
            var y: u0 = 0;
            _ = .{ &x, &y };
            try expectEqual(@as(u0, 0), x << 0);
            try expectEqual(@as(u0, 0), x >> 0);
            try expectEqual(@as(u0, 0), x << y);
            try expectEqual(@as(u0, 0), x >> y);
            try expectEqual(@as(u0, 0), @shlExact(x, 0));
            try expectEqual(@as(u0, 0), @shrExact(x, 0));
            try expectEqual(@as(u0, 0), @shlExact(x, y));
            try expectEqual(@as(u0, 0), @shrExact(x, y));
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "comptime float rem int" {
    comptime {
        const x = @as(f32, 1) % 2;
        try expect(x == 1.0);
    }
}

test "remainder division" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_x86_64 and builtin.target.ofmt != .elf and builtin.target.ofmt != .macho) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    if (builtin.zig_backend == .stage2_llvm and builtin.os.tag == .windows) {
        // https://github.com/ziglang/zig/issues/12602
        return error.SkipZigTest;
    }

    try comptime remdiv(f16);
    try comptime remdiv(f32);
    try comptime remdiv(f64);
    try comptime remdiv(f80);
    try comptime remdiv(f128);
    try remdiv(f16);
    try remdiv(f32);
    try remdiv(f64);
    try remdiv(f80);
    try remdiv(f128);
}

fn remdiv(comptime T: type) !void {
    try expect(@as(T, 1) == @as(T, 1) % @as(T, 2));
    try remdivOne(T, 1, 1, 2);

    try expect(@as(T, 1) == @as(T, 7) % @as(T, 3));
    try remdivOne(T, 1, 7, 3);
}

fn remdivOne(comptime T: type, a: T, b: T, c: T) !void {
    try expect(a == @rem(b, c));
    try expect(a == @mod(b, c));
}

test "float remainder division using @rem" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try comptime frem(f16);
    try comptime frem(f32);
    try comptime frem(f64);
    try comptime frem(f80);
    try comptime frem(f128);
    try frem(f16);
    try frem(f32);
    try frem(f64);
    try frem(f80);
    try frem(f128);
}

fn frem(comptime T: type) !void {
    const epsilon = switch (T) {
        f16 => 1.0,
        f32 => 0.001,
        f64 => 0.00001,
        f80 => 0.000001,
        f128 => 0.0000001,
        else => unreachable,
    };

    try fremOne(T, 6.9, 4.0, 2.9, epsilon);
    try fremOne(T, -6.9, 4.0, -2.9, epsilon);
    try fremOne(T, -5.0, 3.0, -2.0, epsilon);
    try fremOne(T, 3.0, 2.0, 1.0, epsilon);
    try fremOne(T, 1.0, 2.0, 1.0, epsilon);
    try fremOne(T, 0.0, 1.0, 0.0, epsilon);
    try fremOne(T, -0.0, 1.0, -0.0, epsilon);
}

fn fremOne(comptime T: type, a: T, b: T, c: T, epsilon: T) !void {
    try expect(@abs(@rem(a, b) - c) < epsilon);
}

test "float modulo division using @mod" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_x86_64 and builtin.target.ofmt != .elf and builtin.target.ofmt != .macho) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try comptime fmod(f16);
    try comptime fmod(f32);
    try comptime fmod(f64);
    try comptime fmod(f80);
    try comptime fmod(f128);
    try fmod(f16);
    try fmod(f32);
    try fmod(f64);
    try fmod(f80);
    try fmod(f128);
}

fn fmod(comptime T: type) !void {
    const epsilon = switch (T) {
        f16 => 1.0,
        f32 => 0.001,
        f64 => 0.00001,
        f80 => 0.000001,
        f128 => 0.0000001,
        else => unreachable,
    };

    try fmodOne(T, 6.9, 4.0, 2.9, epsilon);
    try fmodOne(T, -6.9, 4.0, 1.1, epsilon);
    try fmodOne(T, -5.0, 3.0, 1.0, epsilon);
    try fmodOne(T, 3.0, 2.0, 1.0, epsilon);
    try fmodOne(T, 1.0, 2.0, 1.0, epsilon);
    try fmodOne(T, 0.0, 1.0, 0.0, epsilon);
    try fmodOne(T, -0.0, 1.0, -0.0, epsilon);
}

fn fmodOne(comptime T: type, a: T, b: T, c: T, epsilon: T) !void {
    try expect(@abs(@mod(@as(T, a), @as(T, b)) - @as(T, c)) < epsilon);
}

test "@round f16" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testRound(f16, 12.0);
    try comptime testRound(f16, 12.0);
}

test "@round f32/f64" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testRound(f64, 12.0);
    try comptime testRound(f64, 12.0);
    try testRound(f32, 12.0);
    try comptime testRound(f32, 12.0);

    const x = 14.0;
    const y = x + 0.4;
    const z = @round(y);
    comptime assert(x == z);
}

test "@round f80" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testRound(f80, 12.0);
    try comptime testRound(f80, 12.0);
}

test "@round f128" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_c and builtin.cpu.arch.isArm()) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testRound(f128, 12.0);
    try comptime testRound(f128, 12.0);
}

fn testRound(comptime T: type, x: T) !void {
    const y = x - 0.5;
    const z = @round(y);
    try expect(x == z);
}

test "vector integer addition" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            var a: @Vector(4, i32) = [_]i32{ 1, 2, 3, 4 };
            var b: @Vector(4, i32) = [_]i32{ 5, 6, 7, 8 };
            _ = .{ &a, &b };
            const result = a + b;
            var result_array: [4]i32 = result;
            const expected = [_]i32{ 6, 8, 10, 12 };
            try expectEqualSlices(i32, &expected, &result_array);
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "NaN comparison" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm() and builtin.target.abi.float() == .soft) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/21234

    try testNanEqNan(f16);
    try testNanEqNan(f32);
    try testNanEqNan(f64);
    try testNanEqNan(f128);
    try comptime testNanEqNan(f16);
    try comptime testNanEqNan(f32);
    try comptime testNanEqNan(f64);
    try comptime testNanEqNan(f128);
}

test "NaN comparison f80" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;

    try testNanEqNan(f80);
    try comptime testNanEqNan(f80);
}

fn testNanEqNan(comptime F: type) !void {
    var nan1 = math.nan(F);
    var nan2 = math.nan(F);
    _ = .{ &nan1, &nan2 };
    try expect(nan1 != nan2);
    try expect(!(nan1 == nan2));
    try expect(!(nan1 > nan2));
    try expect(!(nan1 >= nan2));
    try expect(!(nan1 < nan2));
    try expect(!(nan1 <= nan2));
}

test "vector comparison" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            var a: @Vector(6, i32) = [_]i32{ 1, 3, -1, 5, 7, 9 };
            var b: @Vector(6, i32) = [_]i32{ -1, 3, 0, 6, 10, -10 };
            _ = .{ &a, &b };
            try expect(mem.eql(bool, &@as([6]bool, a < b), &[_]bool{ false, false, true, true, true, false }));
            try expect(mem.eql(bool, &@as([6]bool, a <= b), &[_]bool{ false, true, true, true, true, false }));
            try expect(mem.eql(bool, &@as([6]bool, a == b), &[_]bool{ false, true, false, false, false, false }));
            try expect(mem.eql(bool, &@as([6]bool, a != b), &[_]bool{ true, false, true, true, true, true }));
            try expect(mem.eql(bool, &@as([6]bool, a > b), &[_]bool{ true, false, false, false, false, true }));
            try expect(mem.eql(bool, &@as([6]bool, a >= b), &[_]bool{ true, true, false, false, false, true }));
        }
    };
    try S.doTheTest();
    try comptime S.doTheTest();
}

test "compare undefined literal with comptime_int" {
    var x = undefined == 1;
    // x is now undefined with type bool
    x = true;
    try expect(x);
}

test "signed zeros are represented properly" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_x86_64 and builtin.target.ofmt == .coff) return error.SkipZigTest;

    const S = struct {
        fn doTheTest() !void {
            try testOne(f16);
            try testOne(f32);
            try testOne(f64);
            try testOne(f80);
            try testOne(f128);
            try testOne(c_longdouble);
        }

        fn testOne(comptime T: type) !void {
            const ST = std.meta.Int(.unsigned, @typeInfo(T).float.bits);
            var as_fp_val = -@as(T, 0.0);
            _ = &as_fp_val;
            const as_uint_val: ST = @bitCast(as_fp_val);
            // Ensure the sign bit is set.
            try expect(as_uint_val >> (@typeInfo(T).float.bits - 1) == 1);
        }
    };

    try S.doTheTest();
    try comptime S.doTheTest();
}

test "absFloat" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO

    try testAbsFloat();
    try comptime testAbsFloat();
}
fn testAbsFloat() !void {
    try testAbsFloatOne(-10.05, 10.05);
    try testAbsFloatOne(10.05, 10.05);
}
fn testAbsFloatOne(in: f32, out: f32) !void {
    try expect(@abs(@as(f32, in)) == @as(f32, out));
}

test "mod lazy values" {
    {
        const X = struct { x: u32 };
        const x = @sizeOf(X);
        const y = 1 % x;
        _ = y;
    }
    {
        const X = struct { x: u32 };
        const x = @sizeOf(X);
        const y = x % 1;
        _ = y;
    }
}

test "@clz works on both vector and scalar inputs" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    var x: u32 = 0x1;
    _ = &x;
    var y: @Vector(4, u32) = [_]u32{ 0x1, 0x1, 0x1, 0x1 };
    _ = &y;
    const a = @clz(x);
    const b = @clz(y);
    try std.testing.expectEqual(@as(u6, 31), a);
    try std.testing.expectEqual([_]u6{ 31, 31, 31, 31 }, b);
}

test "runtime comparison to NaN is comptime-known" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm() and builtin.target.abi.float() == .soft) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/21234

    const S = struct {
        fn doTheTest(comptime F: type, x: F) void {
            const nan = math.nan(F);
            if (!(nan != x)) comptime unreachable;
            if (nan == x) comptime unreachable;
            if (nan > x) comptime unreachable;
            if (nan < x) comptime unreachable;
            if (nan >= x) comptime unreachable;
            if (nan <= x) comptime unreachable;
        }
    };

    S.doTheTest(f16, 123.0);
    S.doTheTest(f32, 123.0);
    S.doTheTest(f64, 123.0);
    S.doTheTest(f128, 123.0);
    comptime S.doTheTest(f16, 123.0);
    comptime S.doTheTest(f32, 123.0);
    comptime S.doTheTest(f64, 123.0);
    comptime S.doTheTest(f128, 123.0);
}

test "runtime int comparison to inf is comptime-known" {
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.cpu.arch.isArm() and builtin.target.abi.float() == .soft) return error.SkipZigTest; // https://github.com/ziglang/zig/issues/21234

    const S = struct {
        fn doTheTest(comptime F: type, x: u32) void {
            const inf = math.inf(F);
            if (!(inf != x)) comptime unreachable;
            if (inf == x) comptime unreachable;
            if (x > inf) comptime unreachable;
            if (x >= inf) comptime unreachable;
            if (!(x < inf)) comptime unreachable;
            if (!(x <= inf)) comptime unreachable;
        }
    };

    S.doTheTest(f16, 123);
    S.doTheTest(f32, 123);
    S.doTheTest(f64, 123);
    S.doTheTest(f128, 123);
    comptime S.doTheTest(f16, 123);
    comptime S.doTheTest(f32, 123);
    comptime S.doTheTest(f64, 123);
    comptime S.doTheTest(f128, 123);
}

test "float divide by zero" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_x86_64 and builtin.target.ofmt != .elf and builtin.target.ofmt != .macho) return error.SkipZigTest;

    const S = struct {
        fn doTheTest(comptime F: type, zero: F, one: F) !void {
            try expect(math.isPositiveInf(@divTrunc(one, zero)));
            try expect(math.isPositiveInf(@divFloor(one, zero)));

            try expect(math.isNan(@rem(one, zero)));
            try expect(math.isNan(@mod(one, zero)));
        }
    };

    try S.doTheTest(f16, 0, 1);
    comptime S.doTheTest(f16, 0, 1) catch unreachable;

    try S.doTheTest(f32, 0, 1);
    comptime S.doTheTest(f32, 0, 1) catch unreachable;

    try S.doTheTest(f64, 0, 1);
    comptime S.doTheTest(f64, 0, 1) catch unreachable;

    try S.doTheTest(f80, 0, 1);
    comptime S.doTheTest(f80, 0, 1) catch unreachable;

    try S.doTheTest(f128, 0, 1);
    comptime S.doTheTest(f128, 0, 1) catch unreachable;
}

test "partially-runtime integer vector division would be illegal if vector elements were reordered" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_llvm and builtin.cpu.arch == .hexagon) return error.SkipZigTest;

    var lhs: @Vector(2, i8) = .{ -128, 5 };
    const rhs: @Vector(2, i8) = .{ 1, -1 };

    const expected: @Vector(2, i8) = .{ -128, -5 };

    lhs = lhs; // suppress error

    const trunc = @divTrunc(lhs, rhs);
    try expect(trunc[0] == expected[0]);
    try expect(trunc[1] == expected[1]);

    const floor = @divFloor(lhs, rhs);
    try expect(floor[0] == expected[0]);
    try expect(floor[1] == expected[1]);

    const exact = @divExact(lhs, rhs);
    try expect(exact[0] == expected[0]);
    try expect(exact[1] == expected[1]);
}

test "float vector division of comptime zero by runtime nan is nan" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const ct_zero: @Vector(1, f32) = .{0};
    var rt_nan: @Vector(1, f32) = .{math.nan(f32)};

    rt_nan = rt_nan; // suppress error

    try expect(math.isNan((@divTrunc(ct_zero, rt_nan))[0]));
    try expect(math.isNan((@divFloor(ct_zero, rt_nan))[0]));
    try expect(math.isNan((ct_zero / rt_nan)[0]));
}

test "float vector multiplication of comptime zero by runtime nan is nan" {
    if (builtin.zig_backend == .stage2_aarch64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const ct_zero: @Vector(1, f32) = .{0};
    var rt_nan: @Vector(1, f32) = .{math.nan(f32)};

    rt_nan = rt_nan; // suppress error

    try expect(math.isNan((ct_zero * rt_nan)[0]));
    try expect(math.isNan((rt_nan * ct_zero)[0]));
}

test "comptime float vector division of zero by nan is nan" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const ct_zero: @Vector(1, f32) = .{0};
    const ct_nan: @Vector(1, f32) = .{math.nan(f32)};

    comptime assert(math.isNan((@divTrunc(ct_zero, ct_nan))[0]));
    comptime assert(math.isNan((@divFloor(ct_zero, ct_nan))[0]));
    comptime assert(math.isNan((ct_zero / ct_nan)[0]));
}

test "comptime float vector multiplication of zero by nan is nan" {
    if (builtin.zig_backend == .stage2_wasm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_arm) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_sparc64) return error.SkipZigTest; // TODO
    if (builtin.zig_backend == .stage2_riscv64) return error.SkipZigTest;
    if (builtin.zig_backend == .stage2_spirv) return error.SkipZigTest;

    const ct_zero: @Vector(1, f32) = .{0};
    const ct_nan: @Vector(1, f32) = .{math.nan(f32)};

    comptime assert(math.isNan((ct_zero * ct_nan)[0]));
    comptime assert(math.isNan((ct_nan * ct_zero)[0]));
}
