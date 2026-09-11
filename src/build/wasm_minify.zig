const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try minify(args[1], args[2], init.io, init.gpa);
}

fn minify(fname_in: []const u8, fname_out: []const u8, io: std.Io, gpa: std.mem.Allocator) !void {
    const cwd = std.Io.Dir.cwd();

    // FIRSTLY, run binaryen
    const result = try std.process.run(gpa, io, .{
        .argv = &.{
            "wasm-opt",
            "-all",
            "-Oz",
            "-o",
            fname_out,
            fname_in,
        },
    });

    defer gpa.free(result.stdout);
    defer gpa.free(result.stderr);

    var in_file: []const u8 = fname_out;
    if (!result.term.success()) {
        std.log.warn("wasm-opt failed: {s}", .{result.stderr});
        in_file = fname_in;
    }

    // Read input file
    const input_binary = try cwd.readFileAlloc(io, in_file, gpa, .unlimited);
    defer gpa.free(input_binary);
    var r = std.Io.Reader.fixed(input_binary);

    // Create output writer
    const output_buf = try gpa.alloc(u8, input_binary.len);
    defer gpa.free(output_buf);
    var output_w = std.Io.Writer.fixed(output_buf);

    // Skip magic and version
    const magic_and_version = try r.takeArray(8);
    try output_w.writeAll(magic_and_version);

    // Start parsing WASM module
    while (true) {
        const section_id: std.wasm.Section = try (r.takeEnum(std.wasm.Section, .little) catch |err| switch (err) {
            error.EndOfStream => break,
            else => err,
        });
        const section_length = try r.takeLeb128(u32);

        switch (section_id) {
            .import => {
                const import_count = try r.takeLeb128(u32);

                const import_buf = try gpa.alloc(u8, section_length);
                defer gpa.free(import_buf);
                var import_w = std.Io.Writer.fixed(import_buf);
                try import_w.writeLeb128(import_count);

                for (0..import_count) |_| {
                    const module_length = try r.takeLeb128(u32);
                    const module = try r.take(module_length);

                    const name_length = try r.takeLeb128(u32);
                    const name = try r.take(name_length);
                    _ = name;

                    const extern_kind = try r.takeEnum(std.wasm.ExternalKind, .little);
                    switch (extern_kind) {
                        .function => {
                            const item_index = try r.takeLeb128(u32);

                            // Drop module name completely to save bytes
                            try import_w.writeByte(0);
                            try import_w.writeLeb128(module.len);
                            try import_w.writeAll(module);

                            // Write type and index
                            try import_w.writeByte(@intFromEnum(extern_kind));
                            try import_w.writeLeb128(item_index);
                        },

                        .memory => {
                            const limits: std.wasm.Limits.Flags = try r.takeStruct(std.wasm.Limits.Flags, .little);
                            const min = try r.takeLeb128(u64);
                            const max = if (limits.has_max) try r.takeLeb128(u64) else 0;

                            // Drop module name completely to save bytes
                            try import_w.writeByte(0);
                            try import_w.writeByte(1);
                            try import_w.writeByte('0');

                            // Write limits
                            try import_w.writeByte(@intFromEnum(extern_kind));
                            try import_w.writeStruct(limits, .little);
                            try import_w.writeLeb128(min);
                            if (limits.has_max) try import_w.writeLeb128(max);
                        },

                        else => unreachable,
                    }
                }

                // Ok, now append this to the output module
                try output_w.writeByte(@intFromEnum(section_id));
                try output_w.writeLeb128(import_w.buffered().len);
                try output_w.writeAll(import_w.buffered());
            },

            // Non-export section, pass through directly
            else => {
                try output_w.writeByte(@intFromEnum(section_id));
                try output_w.writeLeb128(section_length);
                const section_data = try r.take(section_length);
                try output_w.writeAll(section_data);
            },
        }
    }

    // Ok, WASM module was optimized successfully!
    // Write output file
    try cwd.writeFile(io, .{
        .data = output_w.buffered(),
        .sub_path = fname_out,
    });
}
