const std = @import("std");

const Module = @import("Module.zig");

pub fn optimize(src: []const u8, w: *std.Io.Writer, gpa: std.mem.Allocator) !void {
    var r = std.Io.Reader.fixed(src);

    // Skip magic and version
    const magic_and_version = try r.takeArray(8);
    try w.writeAll(magic_and_version);

    // Loop over all sections in module
    const module = Module{ .bytes = src };
    var iter = Module.SectionIter.init(module);
    while (iter.next()) |section| {
        try w.writeByte(@intFromEnum(section.type));
        var sr = std.Io.Reader.fixed(section.bytes);

        switch (section.type) {
            .global => {
                const num_globals = try sr.takeLeb128(u32);

                // Add my own things
                var newglobal_w = std.Io.Writer.Allocating.init(gpa);
                const gw = &newglobal_w.writer;
                defer newglobal_w.deinit();

                // Copy original contents
                try gw.writeLeb128(num_globals + 5);
                try gw.writeAll(sr.buffered());

                // Global f32.0
                try gw.writeByte(@intFromEnum(std.wasm.Valtype.f32));
                try gw.writeByte(0);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.f32_const));
                try gw.writeInt(u32, @bitCast(@as(f32, 0)), .little);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.end));

                // Global f32.1
                try gw.writeByte(@intFromEnum(std.wasm.Valtype.f32));
                try gw.writeByte(0);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.f32_const));
                try gw.writeInt(u32, @bitCast(@as(f32, 1)), .little);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.end));

                // Global v128.0000
                try gw.writeByte(@intFromEnum(std.wasm.Valtype.v128));
                try gw.writeByte(0);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.simd_prefix));
                try gw.writeLeb128(@intFromEnum(std.wasm.SimdOpcode.v128_const));
                try gw.writeAll(std.mem.asBytes(&[4]f32{ 0, 0, 0, 0 }));
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.end));

                // Global v128.0001
                try gw.writeByte(@intFromEnum(std.wasm.Valtype.v128));
                try gw.writeByte(0);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.simd_prefix));
                try gw.writeLeb128(@intFromEnum(std.wasm.SimdOpcode.v128_const));
                try gw.writeAll(std.mem.asBytes(&[4]f32{ 0, 0, 0, 1 }));
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.end));

                // Global v128.1111
                try gw.writeByte(@intFromEnum(std.wasm.Valtype.v128));
                try gw.writeByte(0);
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.simd_prefix));
                try gw.writeLeb128(@intFromEnum(std.wasm.SimdOpcode.v128_const));
                try gw.writeAll(std.mem.asBytes(&[4]f32{ 1, 1, 1, 1 }));
                try gw.writeByte(@intFromEnum(std.wasm.Opcode.end));

                // Now write this back
                const content = newglobal_w.written();
                try w.writeLeb128(content.len);
                try w.writeAll(content);
            },

            .import => {
                var import_iter = Module.ImportIter.init(module).?;

                const import_buf = try gpa.alloc(u8, section.bytes.len);
                defer gpa.free(import_buf);
                var import_w = std.Io.Writer.fixed(import_buf);
                try import_w.writeLeb128(import_iter.num_imports);

                while (import_iter.next()) |import| {
                    switch (import.type) {
                        .function => |fn_type| {
                            // Drop namespace completely to save bytes
                            try import_w.writeByte(0);
                            try import_w.writeLeb128(import.namespace.len);
                            try import_w.writeAll(import.namespace);

                            // Write type and index
                            try import_w.writeByte(@intFromEnum(std.meta.activeTag(import.type)));
                            try import_w.writeLeb128(fn_type);
                        },

                        .memory => |mem_type| {
                            // Drop namespace completely to save bytes
                            try import_w.writeByte(0);
                            try import_w.writeByte(1);
                            try import_w.writeByte('0');

                            // Write limits
                            try import_w.writeByte(@intFromEnum(std.meta.activeTag(import.type)));
                            try import_w.writeStruct(mem_type.limits.flags, .little);
                            try import_w.writeLeb128(mem_type.limits.min);
                            if (mem_type.limits.max != 0) try import_w.writeLeb128(mem_type.limits.max);
                        },

                        else => unreachable,
                    }
                }

                // Ok, now append this to the output module
                const content = import_w.buffered();
                try w.writeLeb128(content.len);
                try w.writeAll(content);
            },

            .code => {
                const num_globals: u32 = blk: {
                    const global_section = module.getSectionByType(.global) orelse break :blk 0;
                    var gr = std.Io.Reader.fixed(global_section.bytes);
                    break :blk gr.takeLeb128(u32) catch unreachable;
                };

                var section_w = std.Io.Writer.Allocating.init(gpa);
                defer section_w.deinit();

                var code_iter = Module.CodeIter.init(module).?;
                try section_w.writer.writeLeb128(code_iter.num_entries);

                while (code_iter.next()) |code| {
                    var code_w = std.Io.Writer.Allocating.init(gpa);
                    defer code_w.deinit();

                    // Write locals
                    try code_w.writer.writeAll(code.getLocals());

                    // Optimize instructions
                    var opt = CodeOptimizer{
                        .w = &code_w.writer,
                        .num_globals = num_globals,
                    };
                    var instr_iter = Module.InstructionIter{ .r = .fixed(code.getInstructions()) };
                    while (instr_iter.next()) |instr| {
                        try opt.optimizeInstruction(instr);
                    }

                    // Write this back
                    const content = code_w.written();
                    try section_w.writer.writeLeb128(content.len);
                    try section_w.writer.writeAll(content);
                }

                // Write this back
                const content = section_w.written();
                try w.writeLeb128(content.len);
                try w.writeAll(content);
            },

            // Don't care mate
            else => {
                try w.writeLeb128(section.bytes.len);
                try w.writeAll(section.bytes);
            },
        }
    }
}

const Error = error{} || std.Io.Writer.Error;

const CodeOptimizer = struct {
    w: *std.Io.Writer,
    num_globals: u32,

    const Vi8x16 = @Vector(16, i8);
    const Vi16x8 = @Vector(8, i16);
    const Vi32x4 = @Vector(4, i32);
    const Vf32x4 = @Vector(4, f32);

    fn optimizeInstruction(this: *CodeOptimizer, instr_r: Module.Instruction) Error!void {
        const result = switch (instr_r) {
            .page0 => |instr| try this.optimizePage0(instr),
            .misc => false,
            .simd => |instr| try this.optimizeSimd(instr),
        };

        if (!result) {
            try this.emitInstruction(instr_r);
        }
    }

    fn emitInstruction(this: *CodeOptimizer, instr_r: Module.Instruction) Error!void {
        const w = this.w;

        switch (instr_r) {
            .page0 => |instr| {
                try w.writeByte(@intFromEnum(instr.opcode));
                switch (instr.operands) {
                    .none => {},
                    .branch_table => |bt| {
                        try w.writeAll(bt);
                    },
                    .idx => |val| try w.writeLeb128(val),
                    .idx2 => |val| {
                        try w.writeLeb128(val[0]);
                        try w.writeLeb128(val[1]);
                    },
                    .memarg => |val| {
                        try w.writeLeb128(val.alignment);
                        try w.writeLeb128(val.offset);
                    },

                    .f32 => |val| try w.writeInt(u32, @bitCast(val), .little),
                    .f64 => |val| try w.writeInt(u64, @bitCast(val), .little),
                    .i32 => |val| try w.writeLeb128(val),
                    .i64 => |val| try w.writeLeb128(val),

                    .i33 => |val| try w.writeLeb128(val),
                }
            },
            .misc => |instr| {
                try w.writeByte(@intFromEnum(std.wasm.Opcode.misc_prefix));
                try w.writeLeb128(@intFromEnum(instr.opcode));

                switch (instr.operands) {
                    .none => {},
                    .idx => |val| try w.writeLeb128(val),
                    .idx2 => |val| {
                        try w.writeLeb128(val[0]);
                        try w.writeLeb128(val[1]);
                    },
                }
            },
            .simd => |instr| {
                try w.writeByte(@intFromEnum(std.wasm.Opcode.simd_prefix));
                try w.writeLeb128(@intFromEnum(instr.opcode));

                switch (instr.operands) {
                    .none => {},
                    .memarg => |val| {
                        try w.writeLeb128(val.alignment);
                        try w.writeLeb128(val.offset);
                    },
                    .lane => |val| try w.writeByte(val),
                    .memarg_lane => |val| {
                        try w.writeLeb128(val[0].alignment);
                        try w.writeLeb128(val[0].offset);
                        try w.writeByte(val[1]);
                    },
                    .v128 => |val| {
                        try w.writeAll(&val);
                    },
                }
            },
        }
    }

    fn optimizePage0(this: *CodeOptimizer, instr: Module.Instruction.Page0) Error!bool {
        return switch (instr.opcode) {
            .f32_const => try this.constFloat(instr.operands.f32),

            else => false,
        };
    }

    fn optimizeSimd(this: *CodeOptimizer, instr: Module.Instruction.Simd) Error!bool {
        return switch (instr.opcode) {
            .v128_const => try this.constVector(instr.operands.v128),

            else => false,
        };
    }

    fn constFloat(this: *CodeOptimizer, val: f32) Error!bool {
        if (val == 0) {
            try this.emitInstruction(.{ .page0 = .{ .opcode = .global_get, .operands = .{ .idx = this.num_globals + 0 } } });
            return true;
        }

        if (val == 1) {
            try this.emitInstruction(.{ .page0 = .{ .opcode = .global_get, .operands = .{ .idx = this.num_globals + 1 } } });
            return true;
        }

        // This is an int, try to optimize
        if (@trunc(val) == val and val >= -64 and val < 64) {
            const intval: i32 = @trunc(val);

            try this.emitInstruction(.{ .page0 = .{ .opcode = .i32_const, .operands = .{ .i32 = intval } } });
            try this.emitInstruction(.{ .page0 = .{ .opcode = .f32_convert_i32_s } });
            return true;
        }

        // Nope, just emit the const float
        return false;
    }

    fn constVector(this: *CodeOptimizer, val: [16]u8) Error!bool {
        const i8x16: Vi8x16 = @bitCast(val);
        const i16x8: Vi16x8 = @bitCast(val);
        const i32x4: Vi32x4 = @bitCast(val);
        const f32x4: Vf32x4 = @bitCast(val);

        _ = i32x4;

        // Floating point constants
        if (@reduce(.And, f32x4 == @as(Vf32x4, @splat(0)))) {
            try this.emitInstruction(.{ .page0 = .{ .opcode = .global_get, .operands = .{ .idx = this.num_globals + 2 } } });
            return true;
        }
        if (@reduce(.And, f32x4 == @as(Vf32x4, .{ 0, 0, 0, 1 }))) {
            try this.emitInstruction(.{ .page0 = .{ .opcode = .global_get, .operands = .{ .idx = this.num_globals + 3 } } });
            return true;
        }
        if (@reduce(.And, f32x4 == @as(Vf32x4, @splat(1)))) {
            try this.emitInstruction(.{ .page0 = .{ .opcode = .global_get, .operands = .{ .idx = this.num_globals + 4 } } });
            return true;
        }

        // If all elements are the same...
        if (try this.optimizeSplat(i8x16)) return true;
        if (try this.optimizeSplat(i16x8)) return true;
        if (try this.optimizeSplat(f32x4)) return true;

        // If only 1 element if off...
        if (try this.optimizeSplatReplace(i8x16)) return true;
        if (try this.optimizeSplatReplace(i16x8)) return true;
        if (try this.optimizeSplatReplace(f32x4)) return true;

        return false;
    }

    fn optimizeSplat(this: *CodeOptimizer, val: anytype) Error!bool {
        const Vec = @TypeOf(val);

        if (@reduce(.And, val == @as(Vec, @splat(val[0])))) {
            try this.emitSplat(val[0]);
            return true;
        }

        return false;
    }

    fn optimizeSplatReplace(this: *CodeOptimizer, val: anytype) Error!bool {
        const Vec = @TypeOf(val);
        const vec_info = @typeInfo(Vec).vector;

        inline for (0..vec_info.len) |lane| {
            const this_elem = val[lane];
            const other_elem = if (lane == 0) val[1] else val[0];

            var check_vec = val;
            check_vec[lane] = other_elem;

            // Are all elements except one the same?
            if (@reduce(.And, check_vec == @as(Vec, @splat(other_elem)))) {
                // Yes! Emit that vector
                try this.emitSplat(other_elem);

                // Ok, now emit single element
                try this.emitConst(this_elem);

                // Now replace lane in vector
                try this.emitInstruction(.{
                    .simd = .{
                        .opcode = switch (vec_info.child) {
                            i8 => .i8x16_replace_lane,
                            i16 => .i16x8_replace_lane,
                            i32 => .i32x4_replace_lane,
                            f32 => .f32x4_replace_lane,

                            else => @compileError("unsupported vector element " ++ @typeName(vec_info.child)),
                        },
                        .operands = .{ .lane = @truncate(lane) },
                    },
                });

                return true;
            }
        }

        return false;
    }

    fn emitConst(this: *CodeOptimizer, val: anytype) Error!void {
        switch (@TypeOf(val)) {
            f32 => try this.optimizeInstruction(.{ .page0 = .{ .opcode = .f32_const, .operands = .{ .f32 = val } } }),
            i32, i16, i8 => try this.optimizeInstruction(.{ .page0 = .{ .opcode = .i32_const, .operands = .{ .i32 = val } } }),
            else => @compileError("unsupported const type " ++ @typeName(@TypeOf(val))),
        }
    }

    fn emitSplat(this: *CodeOptimizer, val: anytype) Error!void {
        const Val = @TypeOf(val);

        try this.emitConst(val);

        try this.emitInstruction(.{
            .simd = .{
                .opcode = switch (Val) {
                    i8 => .i8x16_splat,
                    i16 => .i16x8_splat,
                    i32 => .i32x4_splat,
                    f32 => .f32x4_splat,

                    else => @compileError("unsupported vector element " ++ @typeName(Val)),
                },
            },
        });
    }
};
