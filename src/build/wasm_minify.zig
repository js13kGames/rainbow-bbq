const std = @import("std");

const optimize = @import("wasm/optimize.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try minify(args[1], args[2], init.io, init.gpa, args[3][0] == '1');
}

fn minify(fname_in: []const u8, fname_out: []const u8, io: std.Io, gpa: std.mem.Allocator, minify_code: bool) !void {
    const cwd = std.Io.Dir.cwd();

    // FIRSTLY, run binaryen
    var in_file: []const u8 = fname_in;
    if (minify_code) {
        const result = try std.process.run(gpa, io, .{
            .argv = &.{
                "wasm-opt",
                "--enable-nontrapping-float-to-int",
                "--enable-simd",
                "--enable-bulk-memory",
                "--enable-multivalue",
                "--enable-sign-ext",
                "-Oz",
                "-o",
                fname_out,
                fname_in,
            },
        });

        defer gpa.free(result.stdout);
        defer gpa.free(result.stderr);

        in_file = fname_out;
        if (!result.term.success()) {
            std.log.warn("wasm-opt failed: {s}", .{result.stderr});
            in_file = fname_in;
        }
    }

    // Read input file
    const input_binary = try cwd.readFileAlloc(io, in_file, gpa, .unlimited);
    defer gpa.free(input_binary);

    // Create output writer
    var output_w = std.Io.Writer.Allocating.init(gpa);
    defer output_w.deinit();

    try optimize.optimize(input_binary, &output_w.writer, gpa, minify_code);

    // Ok, WASM module was optimized successfully!
    // Write output file
    try cwd.writeFile(io, .{
        .data = output_w.written(),
        .sub_path = fname_out,
    });
}
