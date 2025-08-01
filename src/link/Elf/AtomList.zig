value: i64 = 0,
size: u64 = 0,
alignment: Atom.Alignment = .@"1",
output_section_index: u32 = 0,
// atoms: std.ArrayListUnmanaged(Elf.Ref) = .empty,
atoms: std.AutoArrayHashMapUnmanaged(Elf.Ref, void) = .empty,

dirty: bool = true,

pub fn deinit(list: *AtomList, allocator: Allocator) void {
    list.atoms.deinit(allocator);
}

pub fn address(list: AtomList, elf_file: *Elf) i64 {
    const shdr = elf_file.sections.items(.shdr)[list.output_section_index];
    return @as(i64, @intCast(shdr.sh_addr)) + list.value;
}

pub fn offset(list: AtomList, elf_file: *Elf) u64 {
    const shdr = elf_file.sections.items(.shdr)[list.output_section_index];
    return shdr.sh_offset + @as(u64, @intCast(list.value));
}

pub fn updateSize(list: *AtomList, elf_file: *Elf) void {
    assert(list.dirty);
    for (list.atoms.keys()) |ref| {
        const atom_ptr = elf_file.atom(ref).?;
        assert(atom_ptr.alive);
        const off = atom_ptr.alignment.forward(list.size);
        const padding = off - list.size;
        atom_ptr.value = @intCast(off);
        list.size += padding + atom_ptr.size;
        list.alignment = list.alignment.max(atom_ptr.alignment);
    }
}

pub fn allocate(list: *AtomList, elf_file: *Elf) !void {
    assert(list.dirty);

    const alloc_res = try elf_file.allocateChunk(.{
        .shndx = list.output_section_index,
        .size = list.size,
        .alignment = list.alignment,
        .requires_padding = false,
    });
    list.value = @intCast(alloc_res.value);

    log.debug("allocated atom_list({d}) at 0x{x}", .{ list.output_section_index, list.address(elf_file) });

    const slice = elf_file.sections.slice();
    const shdr = &slice.items(.shdr)[list.output_section_index];
    const last_atom_ref = &slice.items(.last_atom)[list.output_section_index];

    const expand_section = if (elf_file.atom(alloc_res.placement)) |placement_atom|
        placement_atom.nextAtom(elf_file) == null
    else
        true;
    if (expand_section) last_atom_ref.* = list.lastAtom(elf_file).ref();
    shdr.sh_addralign = @max(shdr.sh_addralign, list.alignment.toByteUnits().?);

    // This currently ignores Thunks as valid chunks.
    {
        var idx: usize = 0;
        while (idx < list.atoms.keys().len) : (idx += 1) {
            const curr_atom_ptr = elf_file.atom(list.atoms.keys()[idx]).?;
            if (idx > 0) {
                curr_atom_ptr.prev_atom_ref = list.atoms.keys()[idx - 1];
            }
            if (idx + 1 < list.atoms.keys().len) {
                curr_atom_ptr.next_atom_ref = list.atoms.keys()[idx + 1];
            }
        }
    }

    if (elf_file.atom(alloc_res.placement)) |placement_atom| {
        list.firstAtom(elf_file).prev_atom_ref = placement_atom.ref();
        list.lastAtom(elf_file).next_atom_ref = placement_atom.next_atom_ref;
        placement_atom.next_atom_ref = list.firstAtom(elf_file).ref();
    }

    // If we had a link from Atom to parent AtomList we would not need to
    // update Atom's value or osec index.
    for (list.atoms.keys()) |ref| {
        const atom_ptr = elf_file.atom(ref).?;
        atom_ptr.output_section_index = list.output_section_index;
        atom_ptr.value += list.value;
    }

    list.dirty = false;
}

pub fn write(list: AtomList, buffer: *std.ArrayList(u8), undefs: anytype, elf_file: *Elf) !void {
    const gpa = elf_file.base.comp.gpa;
    const osec = elf_file.sections.items(.shdr)[list.output_section_index];
    assert(osec.sh_type != elf.SHT_NOBITS);
    assert(!list.dirty);

    log.debug("writing atoms in section '{s}'", .{elf_file.getShString(osec.sh_name)});

    const list_size = math.cast(usize, list.size) orelse return error.Overflow;
    try buffer.ensureUnusedCapacity(list_size);
    buffer.appendNTimesAssumeCapacity(0, list_size);

    for (list.atoms.keys()) |ref| {
        const atom_ptr = elf_file.atom(ref).?;
        assert(atom_ptr.alive);

        const off = math.cast(usize, atom_ptr.value - list.value) orelse return error.Overflow;
        const size = math.cast(usize, atom_ptr.size) orelse return error.Overflow;

        log.debug("  atom({f}) at 0x{x}", .{ ref, list.offset(elf_file) + off });

        const object = atom_ptr.file(elf_file).?.object;
        const code = try object.codeDecompressAlloc(elf_file, ref.index);
        defer gpa.free(code);
        const out_code = buffer.items[off..][0..size];
        @memcpy(out_code, code);

        if (osec.sh_flags & elf.SHF_ALLOC == 0)
            try atom_ptr.resolveRelocsNonAlloc(elf_file, out_code, undefs)
        else
            try atom_ptr.resolveRelocsAlloc(elf_file, out_code);
    }

    try elf_file.base.file.?.pwriteAll(buffer.items, list.offset(elf_file));
    buffer.clearRetainingCapacity();
}

pub fn writeRelocatable(list: AtomList, buffer: *std.ArrayList(u8), elf_file: *Elf) !void {
    const gpa = elf_file.base.comp.gpa;
    const osec = elf_file.sections.items(.shdr)[list.output_section_index];
    assert(osec.sh_type != elf.SHT_NOBITS);

    log.debug("writing atoms in section '{s}'", .{elf_file.getShString(osec.sh_name)});

    const list_size = math.cast(usize, list.size) orelse return error.Overflow;
    try buffer.ensureUnusedCapacity(list_size);
    buffer.appendNTimesAssumeCapacity(0, list_size);

    for (list.atoms.keys()) |ref| {
        const atom_ptr = elf_file.atom(ref).?;
        assert(atom_ptr.alive);

        const off = math.cast(usize, atom_ptr.value - list.value) orelse return error.Overflow;
        const size = math.cast(usize, atom_ptr.size) orelse return error.Overflow;

        log.debug("  atom({f}) at 0x{x}", .{ ref, list.offset(elf_file) + off });

        const object = atom_ptr.file(elf_file).?.object;
        const code = try object.codeDecompressAlloc(elf_file, ref.index);
        defer gpa.free(code);
        const out_code = buffer.items[off..][0..size];
        @memcpy(out_code, code);
    }

    try elf_file.base.file.?.pwriteAll(buffer.items, list.offset(elf_file));
    buffer.clearRetainingCapacity();
}

pub fn firstAtom(list: AtomList, elf_file: *Elf) *Atom {
    assert(list.atoms.keys().len > 0);
    return elf_file.atom(list.atoms.keys()[0]).?;
}

pub fn lastAtom(list: AtomList, elf_file: *Elf) *Atom {
    assert(list.atoms.keys().len > 0);
    return elf_file.atom(list.atoms.keys()[list.atoms.keys().len - 1]).?;
}

const Format = struct {
    atom_list: AtomList,
    elf_file: *Elf,

    fn default(f: Format, writer: *std.io.Writer) std.io.Writer.Error!void {
        const list = f.atom_list;
        try writer.print("list : @{x} : shdr({d}) : align({x}) : size({x})", .{
            list.address(f.elf_file),
            list.output_section_index,
            list.alignment.toByteUnits() orelse 0,
            list.size,
        });
        try writer.writeAll(" : atoms{ ");
        for (list.atoms.keys(), 0..) |ref, i| {
            try writer.print("{f}", .{ref});
            if (i < list.atoms.keys().len - 1) try writer.writeAll(", ");
        }
        try writer.writeAll(" }");
    }
};

pub fn fmt(atom_list: AtomList, elf_file: *Elf) std.fmt.Formatter(Format, Format.default) {
    return .{ .data = .{ .atom_list = atom_list, .elf_file = elf_file } };
}

const assert = std.debug.assert;
const elf = std.elf;
const log = std.log.scoped(.link);
const math = std.math;
const std = @import("std");

const Allocator = std.mem.Allocator;
const Atom = @import("Atom.zig");
const AtomList = @This();
const Elf = @import("../Elf.zig");
const Object = @import("Object.zig");
