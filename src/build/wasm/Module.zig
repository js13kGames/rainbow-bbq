const Module = @This();

const std = @import("std");

bytes: []const u8,

pub const Section = struct {
    type: std.wasm.Section,
    bytes: []const u8,

    pub const Custom = struct {
        name: []const u8,
        bytes: []const u8,
    };

    pub fn asCustom(this: Section) ?Custom {
        if (this.type != .custom) return null;
        var r = std.Io.Reader.fixed(this.bytes);

        const name_len = r.takeLeb128(u32) catch unreachable;
        const name = r.take(name_len) catch unreachable;

        return .{
            .name = name,
            .bytes = r.buffered(),
        };
    }
};

pub const SectionIter = struct {
    r: std.Io.Reader,

    pub fn init(module: Module) SectionIter {
        return .{ .r = .fixed(module.bytes[8..]) };
    }

    pub fn next(this: *SectionIter) ?Section {
        if (this.r.seek == this.r.end) return null;

        const section_type = this.r.takeEnum(std.wasm.Section, .little) catch unreachable;
        const section_length = this.r.takeLeb128(u32) catch unreachable;
        const section_data = this.r.take(section_length) catch unreachable;

        return .{
            .type = section_type,
            .bytes = section_data,
        };
    }
};

pub fn numSections(this: Module) usize {
    var iter = SectionIter.init(this);

    var num_sections: usize = 0;
    while (iter.next()) |_| {
        num_sections += 1;
    }

    return num_sections;
}

pub fn getSectionByIndex(this: Module, section_id: usize) Section {
    var iter = SectionIter.init(this);

    var seen = section_id;
    while (iter.next()) |section| {
        if (seen == section_id) return section;

        seen += 1;
    }

    @panic("bad");
}

pub fn getSectionByType(this: Module, section_type: std.wasm.Section) ?Section {
    var iter = SectionIter.init(this);

    while (iter.next()) |section| {
        if (section.type == section_type) {
            return section;
        }
    }

    return null;
}

pub fn getSectionByName(this: Module, section_name: []const u8) ?Section.Custom {
    var iter = SectionIter.init(this);

    while (iter.next()) |section| {
        const custom = section.asCustom() orelse continue;

        if (std.mem.eql(u8, section_name, custom.name)) {
            return custom;
        }
    }

    return null;
}

pub const FunctionType = struct {
    params: []const u8,
    results: []const u8,
};

pub const MemoryType = struct {
    limits: std.wasm.Limits,
};

pub const ExternType = union(std.wasm.ExternalKind) {
    function: u32,
    table: void,
    memory: MemoryType,
    global: void,
};

pub fn getType(this: Module, index: usize) ?FunctionType {
    const type_section = this.getSectionByType(.type) orelse return null;
    var r = std.Io.Reader.fixed(type_section.bytes);

    const num_types = r.takeLeb128(u32) catch unreachable;
    if (index >= num_types) return null;

    // Find MY type
    var seen: usize = 0;
    while (r.seek != r.end) {
        const b = r.takeByte() catch unreachable;
        std.debug.assert(b == std.wasm.function_type);

        const num_params = r.takeLeb128(usize) catch unreachable;
        const params = r.take(num_params) catch unreachable;

        const num_results = r.takeLeb128(usize) catch unreachable;
        const results = r.take(num_results) catch unreachable;

        if (seen == index) return .{
            .params = params,
            .results = results,
        };
        seen += 1;
    }

    return null;
}

pub fn getFunctionType(this: Module, index: usize) ?FunctionType {
    const fn_section = this.getSectionByType(.function) orelse return null;
    var r = std.Io.Reader.fixed(fn_section.bytes);

    const true_index = index - this.getNumImportedFunctions();
    const num_fns = r.takeLeb128(u32) catch unreachable;
    if (true_index >= num_fns) return null;

    // Find MY type
    var seen: usize = 0;
    while (r.seek != r.end) {
        const type_id = r.takeLeb128(u32) catch unreachable;
        if (seen == true_index) return this.getType(type_id);
        seen += 1;
    }

    return null;
}

pub fn getFunctionName(module: Module, fn_index: usize) ?[]const u8 {
    const name_section = module.getSectionByName("name") orelse return null;
    var r = std.Io.Reader.fixed(name_section.bytes);

    while (r.seek < r.end) {
        const subsection_id = r.takeEnum(std.wasm.NameSubsection, .little) catch unreachable;
        const subsection_length = r.takeLeb128(u32) catch unreachable;
        const subsection_data = r.take(subsection_length) catch unreachable;
        var sr = std.Io.Reader.fixed(subsection_data);

        if (subsection_id == .function) {
            const num_names = sr.takeLeb128(u32) catch unreachable;

            for (0..num_names) |_| {
                const function_id = sr.takeLeb128(u32) catch unreachable;
                const function_name_len = sr.takeLeb128(u32) catch unreachable;
                const function_name = sr.take(function_name_len) catch unreachable;

                if (function_id == fn_index) {
                    return function_name;
                }
            }
        }
    }

    return null;
}

pub const Import = struct {
    namespace: []const u8,
    name: []const u8,
    type: ExternType,
};

pub const ImportIter = struct {
    r: std.Io.Reader,
    module: Module,
    num_imports: u32,

    pub fn init(module: Module) ?ImportIter {
        const import_section = module.getSectionByType(.import) orelse return null;

        var r = std.Io.Reader.fixed(import_section.bytes);
        const num_imports = r.takeLeb128(u32) catch unreachable;

        return .{
            .r = r,
            .module = module,
            .num_imports = num_imports,
        };
    }

    pub fn next(this: *ImportIter) ?Import {
        if (this.r.seek == this.r.end) return null;

        const namespace_len = this.r.takeLeb128(u32) catch unreachable;
        const namespace = this.r.take(namespace_len) catch unreachable;

        const name_len = this.r.takeLeb128(u32) catch unreachable;
        const name = this.r.take(name_len) catch unreachable;

        const external_kind = this.r.takeEnum(std.wasm.ExternalKind, .little) catch unreachable;
        return .{
            .namespace = namespace,
            .name = name,
            .type = switch (external_kind) {
                .function => blk: {
                    const fn_type = this.r.takeLeb128(u32) catch unreachable;
                    break :blk .{ .function = fn_type };
                },

                .memory => blk: {
                    const flags = this.r.takeStruct(std.wasm.Limits.Flags, .little) catch unreachable;
                    const min = this.r.takeLeb128(u32) catch unreachable;
                    const max = if (flags.has_max) (this.r.takeLeb128(u32) catch unreachable) else 0;

                    break :blk .{ .memory = .{
                        .limits = .{
                            .flags = flags,
                            .min = min,
                            .max = max,
                        },
                    } };
                },

                else => unreachable,
            },
        };
    }
};

pub fn getNumImportedFunctions(this: Module) usize {
    var iter = ImportIter.init(this).?;
    var seen_fn: usize = 0;
    while (iter.next()) |import| {
        if (std.meta.activeTag(import.type) == .function) {
            seen_fn += 1;
        }
    }

    return seen_fn;
}

pub const Code = struct {
    bytes: []const u8,
    index: usize,

    pub fn getLocalType(this: Code, module: Module, local: usize) std.wasm.Valtype {
        // Look through params first
        const fn_type = module.getFunctionType(this.index).?;
        if (fn_type.params.len > local) {
            return @bitCast(fn_type.params[local]);
        }

        var r = std.Io.Reader.fixed(this.bytes);
        const local_entries = r.takeLeb128(u32) catch unreachable;

        var seen = fn_type.params.len;
        for (0..local_entries) |_| {
            const count = r.takeLeb128(u32) catch unreachable;
            const kind = r.takeEnum(std.wasm.Valtype, .little) catch unreachable;

            seen += count;
            if (local < seen) {
                return kind;
            }
        }

        @panic("OOB local");
    }

    pub fn getLocals(this: Code) []const u8 {
        var r = std.Io.Reader.fixed(this.bytes);
        const local_entries = r.takeLeb128(u32) catch unreachable;

        for (0..local_entries) |_| {
            _ = r.takeLeb128(u32) catch unreachable;
            _ = r.takeEnum(std.wasm.Valtype, .little) catch unreachable;
        }

        return r.buffer[0..r.seek];
    }

    pub fn getInstructions(this: Code) []const u8 {
        var r = std.Io.Reader.fixed(this.bytes);
        const local_entries = r.takeLeb128(u32) catch unreachable;

        for (0..local_entries) |_| {
            _ = r.takeLeb128(u32) catch unreachable;
            _ = r.takeEnum(std.wasm.Valtype, .little) catch unreachable;
        }

        return r.buffered();
    }
};

pub const CodeIter = struct {
    r: std.Io.Reader,
    n: usize,
    num_entries: u32,

    pub fn init(module: Module) ?CodeIter {
        const code_section = module.getSectionByType(.code) orelse return null;
        var r = std.Io.Reader.fixed(code_section.bytes);

        const num_entries = r.takeLeb128(u32) catch unreachable;

        return .{
            .r = r,
            .n = module.getNumImportedFunctions(),
            .num_entries = num_entries,
        };
    }

    pub fn next(this: *CodeIter) ?Code {
        if (this.r.seek == this.r.end) return null;

        const code_len = this.r.takeLeb128(u32) catch unreachable;
        const code = this.r.take(code_len) catch unreachable;

        this.n += 1;

        return .{
            .index = this.n - 1,
            .bytes = code,
        };
    }
};

pub const Instruction = union(enum) {
    page0: Page0,
    misc: Misc,
    simd: Simd,

    pub const Page0 = struct {
        opcode: std.wasm.Opcode,
        operands: union(enum) {
            none: void,
            memarg: MemArg,
            branch_table: []const u8, // raw data
            idx: u32,
            idx2: [2]u32,
            i33: i33,
            i32: i32,
            i64: i64,
            f32: f32,
            f64: f64,
        } = .{ .none = {} },
    };

    pub const Misc = struct {
        opcode: std.wasm.MiscOpcode,
        operands: union(enum) {
            none: void,
            idx: u32,
            idx2: [2]u32,
        } = .{ .none = {} },
    };

    pub const Simd = struct {
        opcode: std.wasm.SimdOpcode,
        operands: union(enum) {
            none: void,
            memarg: MemArg,
            lane: u8,
            memarg_lane: struct { MemArg, u8 },
            v128: [16]u8,
        } = .{ .none = {} },
    };

    pub const MemArg = struct {
        alignment: u32,
        offset: u32,
    };
};

pub const InstructionPtr = struct {
    idx: usize,
};

pub const InstructionIter = struct {
    r: std.Io.Reader,

    stack: [64]InstructionPtr = undefined,
    stack_depth: usize = 0,

    pub fn next(this: *InstructionIter) ?Instruction {
        if (this.r.seek >= this.r.end) return null;

        const instr = this.decode(&this.r) catch unreachable;
        return instr;
    }

    fn decode(this: InstructionIter, r: *std.Io.Reader) !Instruction {
        _ = this;
        const opcode = try r.takeEnum(std.wasm.Opcode, .little);

        return switch (opcode) {
            else => std.debug.panic("unimplemented for opcode '{}", .{opcode}),

            .misc_prefix => decodeMisc(r),
            .simd_prefix => decodeSimd(r),

            .@"unreachable", .nop, .@"else", .end, .@"return", .select, .drop => .{ .page0 = .{
                .opcode = opcode,
            } },

            .global_get,
            .global_set,
            .local_get,
            .local_set,
            .local_tee,
            .@"if",
            .br,
            .br_if,
            .memory_grow,
            .memory_size,
            => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{ .idx = try r.takeLeb128(u32) },
            } },

            .call, .block, .loop => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{ .i33 = try r.takeLeb128(i33) },
            } },

            .call_indirect => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{ .idx2 = .{
                    try r.takeLeb128(u32),
                    try r.takeLeb128(u32),
                } },
            } },

            .br_table => blk: {
                const start = r.seek;
                const num_branches = try r.takeLeb128(u32);

                for (0..num_branches) |_| {
                    _ = try r.takeLeb128(u32);
                }
                _ = try r.takeLeb128(u32);
                const end = r.seek;

                break :blk .{ .page0 = .{
                    .opcode = opcode,
                    .operands = .{ .branch_table = r.buffer[start..end] },
                } };
            },

            .i32_const => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{
                    .i32 = try r.takeLeb128(i32),
                },
            } },

            .i64_const => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{
                    .i64 = try r.takeLeb128(i64),
                },
            } },

            .f32_const => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{
                    .f32 = @bitCast(try r.takeInt(u32, .little)),
                },
            } },

            .f64_const => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{
                    .f64 = @bitCast(try r.takeInt(u64, .little)),
                },
            } },

            .i32_add, .i32_sub, .i32_mul, .i32_div_s, .i32_div_u, .i32_rem_s, .i32_rem_u => .{ .page0 = .{ .opcode = opcode } },
            .i64_add, .i64_sub, .i64_mul, .i64_div_s, .i64_div_u, .i64_rem_s, .i64_rem_u => .{ .page0 = .{ .opcode = opcode } },
            .f32_add, .f32_sub, .f32_mul, .f32_div, .f32_neg, .f32_sqrt => .{ .page0 = .{ .opcode = opcode } },
            .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_neg, .f64_sqrt => .{ .page0 = .{ .opcode = opcode } },

            .i32_eq, .i32_eqz, .i32_ne, .i32_le_s, .i32_le_u, .i32_ge_s, .i32_ge_u, .i32_lt_s, .i32_lt_u, .i32_gt_s, .i32_gt_u => .{ .page0 = .{ .opcode = opcode } },
            .i64_eq, .i64_eqz, .i64_ne, .i64_le_s, .i64_le_u, .i64_ge_s, .i64_ge_u, .i64_lt_s, .i64_lt_u, .i64_gt_s, .i64_gt_u => .{ .page0 = .{ .opcode = opcode } },

            .i32_and, .i32_or, .i32_xor, .i32_shl, .i32_shr_s, .i32_shr_u, .i32_rotl, .i32_rotr, .i32_popcnt, .i32_clz, .i32_ctz => .{ .page0 = .{ .opcode = opcode } },
            .i64_and, .i64_or, .i64_xor, .i64_shl, .i64_shr_s, .i64_shr_u, .i64_rotl, .i64_rotr, .i64_popcnt, .i64_clz, .i64_ctz => .{ .page0 = .{ .opcode = opcode } },
            .f32_eq, .f32_ne, .f32_ge, .f32_gt, .f32_lt, .f32_le => .{ .page0 = .{ .opcode = opcode } },
            .f64_eq, .f64_ne, .f64_ge, .f64_gt, .f64_lt, .f64_le => .{ .page0 = .{ .opcode = opcode } },

            .f32_min, .f32_max, .f32_abs, .f32_floor, .f32_trunc, .f32_ceil, .f32_nearest => .{ .page0 = .{ .opcode = opcode } },
            .f64_min, .f64_max, .f64_abs, .f64_floor, .f64_trunc, .f64_ceil, .f64_nearest => .{ .page0 = .{ .opcode = opcode } },

            .i32_load, .i32_load16_s, .i32_load16_u, .i32_load8_s, .i32_load8_u, .i32_store, .i32_store16, .i32_store8 => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{ .memarg = try decodeMemArg(r) },
            } },
            .i64_load, .i64_load32_s, .i64_load32_u, .i64_load16_s, .i64_load16_u, .i64_load8_s, .i64_load8_u, .i64_store, .i64_store32, .i64_store16, .i64_store8 => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{ .memarg = try decodeMemArg(r) },
            } },
            .f32_load, .f32_store, .f64_load, .f64_store => .{ .page0 = .{
                .opcode = opcode,
                .operands = .{ .memarg = try decodeMemArg(r) },
            } },

            .i32_extend16_s, .i32_extend8_s, .i32_reinterpret_f32, .i32_trunc_f32_s, .i32_trunc_f32_u, .i32_trunc_f64_s, .i32_trunc_f64_u, .i32_wrap_i64 => .{ .page0 = .{ .opcode = opcode } },
            .i64_extend16_s, .i64_extend32_s, .i64_extend8_s, .i64_extend_i32_s, .i64_extend_i32_u, .i64_reinterpret_f64, .i64_trunc_f32_s, .i64_trunc_f32_u, .i64_trunc_f64_s, .i64_trunc_f64_u => .{ .page0 = .{ .opcode = opcode } },
            .f32_convert_i32_s, .f32_convert_i32_u, .f32_convert_i64_s, .f32_convert_i64_u, .f32_copysign, .f32_demote_f64, .f32_reinterpret_i32 => .{ .page0 = .{ .opcode = opcode } },
            .f64_convert_i32_s, .f64_convert_i32_u, .f64_convert_i64_s, .f64_convert_i64_u, .f64_copysign, .f64_promote_f32, .f64_reinterpret_i64 => .{ .page0 = .{ .opcode = opcode } },
        };
    }

    fn decodeMisc(r: *std.Io.Reader) !Instruction {
        const opcode: std.wasm.MiscOpcode = @enumFromInt(try r.takeLeb128(u32));

        return switch (opcode) {
            else => std.debug.panic("unimplemented for opcode '{}", .{opcode}),

            .i32_trunc_sat_f32_s, .i32_trunc_sat_f64_s, .i64_trunc_sat_f32_s, .i64_trunc_sat_f64_s, .i32_trunc_sat_f32_u, .i32_trunc_sat_f64_u, .i64_trunc_sat_f32_u, .i64_trunc_sat_f64_u => .{ .misc = .{ .opcode = opcode } },

            .memory_fill => .{ .misc = .{
                .opcode = opcode,
                .operands = .{ .idx = try r.takeLeb128(u32) },
            } },

            .memory_copy => .{ .misc = .{
                .opcode = opcode,
                .operands = .{ .idx2 = .{
                    try r.takeLeb128(u32),
                    try r.takeLeb128(u32),
                } },
            } },
        };
    }

    fn decodeSimd(r: *std.Io.Reader) !Instruction {
        const opcode: std.wasm.SimdOpcode = @enumFromInt(try r.takeLeb128(u32));

        return switch (opcode) {
            else => std.debug.panic("unimplemented for opcode '{}", .{opcode}),

            .v128_load, .v128_store => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .memarg = try decodeMemArg(r) },
            } },

            .i8x16_add, .i8x16_sub, .i8x16_neg => .{ .simd = .{ .opcode = opcode } },
            .i16x8_add, .i16x8_sub, .i16x8_mul, .i16x8_neg, .i16x8_add_sat_s, .i16x8_add_sat_u => .{ .simd = .{ .opcode = opcode } },
            .i32x4_add, .i32x4_sub, .i32x4_mul, .i32x4_neg => .{ .simd = .{ .opcode = opcode } },
            .i64x2_add, .i64x2_sub, .i64x2_mul, .i64x2_neg => .{ .simd = .{ .opcode = opcode } },
            .f32x4_add, .f32x4_sub, .f32x4_mul, .f32x4_div, .f32x4_neg => .{ .simd = .{ .opcode = opcode } },
            .f64x2_add, .f64x2_sub, .f64x2_mul, .f64x2_div, .f64x2_neg => .{ .simd = .{ .opcode = opcode } },

            .v128_and, .v128_andnot, .v128_or, .v128_not, .v128_xor, .v128_bitselect, .v128_any_true => .{ .simd = .{ .opcode = opcode } },
            .i8x16_shl, .i8x16_shr_s, .i8x16_shr_u => .{ .simd = .{ .opcode = opcode } },
            .i16x8_shl, .i16x8_shr_s, .i16x8_shr_u => .{ .simd = .{ .opcode = opcode } },
            .i32x4_shl, .i32x4_shr_s, .i32x4_shr_u => .{ .simd = .{ .opcode = opcode } },
            .i64x2_shl, .i64x2_shr_s, .i64x2_shr_u => .{ .simd = .{ .opcode = opcode } },

            .f32x4_replace_lane, .f64x2_replace_lane, .i16x8_replace_lane, .i32x4_replace_lane, .i64x2_replace_lane, .i8x16_replace_lane => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .lane = try r.takeByte() },
            } },

            .f32x4_extract_lane, .f64x2_extract_lane, .i16x8_extract_lane_s, .i16x8_extract_lane_u, .i32x4_extract_lane, .i64x2_extract_lane, .i8x16_extract_lane_s, .i8x16_extract_lane_u => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .lane = try r.takeByte() },
            } },

            .f32x4_splat, .f64x2_splat, .i8x16_splat, .i16x8_splat, .i32x4_splat, .i64x2_splat => .{ .simd = .{ .opcode = opcode } },

            .i16x8_extadd_pairwise_i8x16_s, .i16x8_extadd_pairwise_i8x16_u, .i32x4_extadd_pairwise_i16x8_s, .i32x4_extadd_pairwise_i16x8_u => .{ .simd = .{ .opcode = opcode } },
            .i16x8_extend_high_i8x16_s, .i16x8_extend_high_i8x16_u, .i32x4_extend_high_i16x8_s, .i32x4_extend_high_i16x8_u, .i64x2_extend_high_i32x4_s, .i64x2_extend_high_i32x4_u => .{ .simd = .{ .opcode = opcode } },
            .i16x8_extend_low_i8x16_s, .i16x8_extend_low_i8x16_u, .i32x4_extend_low_i16x8_s, .i32x4_extend_low_i16x8_u, .i64x2_extend_low_i32x4_s, .i64x2_extend_low_i32x4_u => .{ .simd = .{ .opcode = opcode } },

            .f32x4_convert_i32x4_s, .f32x4_convert_i32x4_u, .f64x2_convert_low_i32x4_s, .f64x2_convert_low_i32x4_u => .{ .simd = .{ .opcode = opcode } },
            .f32x4_trunc, .f64x2_trunc, .i32x4_trunc_sat_f32x4_s, .i32x4_trunc_sat_f64x2_s_zero, .i32x4_trunc_sat_f64x2_u_zero, .i32x4_trunc_sat_f32x4_u => .{ .simd = .{ .opcode = opcode } },

            .v128_load16_lane, .v128_load32_lane, .v128_load64_lane, .v128_load8_lane => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .memarg_lane = .{
                    try decodeMemArg(r),
                    try r.takeByte(),
                } },
            } },

            .v128_load32_zero, .v128_load64_zero, .v128_load16_splat, .v128_load32_splat, .v128_load8_splat, .v128_load64_splat => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .memarg = try decodeMemArg(r) },
            } },

            .v128_store16_lane, .v128_store32_lane, .v128_store64_lane, .v128_store8_lane => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .memarg_lane = .{
                    try decodeMemArg(r),
                    try r.takeByte(),
                } },
            } },

            .v128_const, .i8x16_shuffle => .{ .simd = .{
                .opcode = opcode,
                .operands = .{ .v128 = (try r.takeArray(16)).* },
            } },
        };
    }

    fn decodeMemArg(r: *std.Io.Reader) !Instruction.MemArg {
        return .{
            .alignment = try r.takeLeb128(u32),
            .offset = try r.takeLeb128(u32),
        };
    }
};

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const fname = args[1];
    const src = try cwd.readFileAlloc(init.io, fname, init.gpa, .unlimited);
    defer init.gpa.free(src);

    const module = Module{ .bytes = src };

    // Dump imports
    {
        var iter = ImportIter.init(module).?;
        while (iter.next()) |import| {
            std.log.debug("'{s}' '{s}' {any}", .{ import.namespace, import.name, import.type });
        }
    }

    // Dump functions
    {
        var iter = CodeIter.init(module).?;
        while (iter.next()) |code| {
            const fn_name = module.getFunctionName(code.index).?;
            const fn_type = module.getFunctionType(code.index);
            std.log.debug("{s}: len {}, type {any}", .{ fn_name, code.getInstructions().len, fn_type });

            var instr_iter = InstructionIter{ .r = .fixed(code.getInstructions()) };
            while (instr_iter.next()) |instr| {
                std.log.debug("{any}", .{instr});
            }
        }
    }
}
