const std = @import("std");

const optimize = @import("wasm/optimize.zig");

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    try minify(args[1], args[2], init.io, init.gpa);
}

fn minify(fname_in: []const u8, fname_out: []const u8, io: std.Io, gpa: std.mem.Allocator) !void {
    const cwd = std.Io.Dir.cwd();

    std.log.warn("in: {s}", .{fname_in});
    std.log.warn("out: {s}", .{fname_out});

    // Read input file
    const input_binary = try cwd.readFileAlloc(io, fname_in, gpa, .unlimited);
    defer gpa.free(input_binary);

    // Create output writer
    var output_w = std.Io.Writer.Allocating.init(gpa);
    defer output_w.deinit();

    try optimize.optimize(input_binary, &output_w.writer, gpa);

    // Ok, WASM module was optimized successfully!
    // Write output file
    try cwd.writeFile(io, .{
        .data = output_w.written(),
        .sub_path = fname_out,
    });
}
