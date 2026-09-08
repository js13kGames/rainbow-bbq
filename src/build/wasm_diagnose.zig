const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try diagnnose(args[1], init.io, init.gpa);
}

const Function = struct {
    name: ?[]const u8 = null,
    len: u32,
};

fn diagnnose(fname_in: []const u8, io: std.Io, gpa: std.mem.Allocator) !void {
    const cwd = std.Io.Dir.cwd();

    // Read input file
    const input_binary = try cwd.readFileAlloc(io, fname_in, gpa, .unlimited);
    defer gpa.free(input_binary);
    var r = std.Io.Reader.fixed(input_binary);

    // Skip magic and version
    try r.discardAll(8);

    var functions: []Function = &.{};
    defer gpa.free(functions);

    var imported_functions: usize = 0;
    var total_size: usize = input_binary.len;

    // Start parsing WASM module
    while (r.seek != r.end) {
        const section_start = r.seek;

        const section_id: std.wasm.Section = try r.takeEnum(std.wasm.Section, .little);
        const section_length = try r.takeLeb128(u32);
        var section_name: ?[]const u8 = null;

        switch (section_id) {
            .import => {
                const import_count = try r.takeLeb128(u32);

                for (0..import_count) |_| {
                    const module_length = try r.takeLeb128(u32);
                    const module = try r.take(module_length);
                    _ = module;

                    const name_length = try r.takeLeb128(u32);
                    const name = try r.take(name_length);
                    _ = name;

                    const extern_kind = try r.takeEnum(std.wasm.ExternalKind, .little);
                    switch (extern_kind) {
                        .function => {
                            const item_index = try r.takeLeb128(u32);
                            _ = item_index;
                            imported_functions += 1;
                        },

                        .memory => {
                            const limits: std.wasm.Limits.Flags = try r.takeStruct(std.wasm.Limits.Flags, .little);
                            const min = try r.takeLeb128(u64);
                            const max = if (limits.has_max) try r.takeLeb128(u64) else 0;

                            _ = min;
                            _ = max;
                        },

                        else => unreachable,
                    }
                }
            },

            .code => {
                const num_functions = try r.takeLeb128(u32);
                functions = try gpa.alloc(Function, num_functions);

                for (0..num_functions) |i| {
                    const function_len = try r.takeLeb128(u32);
                    try r.discardAll(function_len);

                    functions[i] = .{
                        .name = null,
                        .len = function_len,
                    };
                }
            },

            .custom => {
                const section_data = try r.take(section_length);
                var cr = std.Io.Reader.fixed(section_data);
                total_size -= r.seek - section_start;

                const name_len = try cr.takeLeb128(u32);
                const name = try cr.take(name_len);
                section_name = name;

                // Is this the name of things?
                if (std.mem.eql(u8, name, "name")) {
                    while (cr.seek != cr.end) {
                        const subsection_id = try cr.takeEnum(std.wasm.NameSubsection, .little);
                        const subsection_length = try cr.takeLeb128(u32);
                        const subsection_data = try cr.take(subsection_length);
                        var sr = std.Io.Reader.fixed(subsection_data);

                        if (subsection_id == .function) {
                            const num_names = try sr.takeLeb128(u32);

                            for (0..num_names) |_| {
                                const function_id = try sr.takeLeb128(u32);
                                const function_name_len = try sr.takeLeb128(u32);
                                const function_name = try sr.take(function_name_len);

                                if (imported_functions <= function_id) {
                                    functions[function_id - imported_functions].name = function_name;
                                }
                            }
                        }
                    }
                }
            },

            // Non-export section, pass through directly
            else => {
                try r.discardAll(section_length);
            },
        }

        if (section_name) |name| {
            if (false) {
                std.log.debug("section {} '{s}', {} bytes", .{ section_id, name, section_length });
            }
        } else {
            std.log.debug("section {}, {} bytes", .{ section_id, section_length });
        }
    }

    // List functions
    for (functions) |function| {
        std.log.debug("  fn '{s}': {} bytes", .{ function.name orelse "", function.len });
    }
    std.log.debug("total size: {} bytes", .{total_size});
}
