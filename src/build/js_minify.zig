//! Opinionated JS minifier.
//! It imposes some restrictions on the input JS code:
//! * Semicolons are required, always
//! * No use of the `arguments` keyword
//! * Assumes true === 1 and false === 0

const std = @import("std");

const tokenizer = @import("js/tokenizer.zig");
const parser = @import("js/parser.zig");
const optimizer = @import("js/optimize.zig");
const printer = @import("js/printer.zig");
const ast = @import("js/ast.zig");
const debug_printer = @import("ast_printer.zig").For(ast);
const Token = tokenizer.Token;

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len < 3) {
        std.log.err("usage: {s} <input file path> <output file path>", .{args[0]});
        return error.InvalidArgumentCount;
    }

    const cwd = std.Io.Dir.cwd();

    const fname_in = args[1];
    const src = try cwd.readFileAlloc(init.io, fname_in, init.gpa, .unlimited);
    defer init.gpa.free(src);

    const fname_out = args[2];
    var out_file = try cwd.createFile(init.io, fname_out, .{});
    var out_buf: [2048]u8 = undefined;
    var w = out_file.writer(init.io, &out_buf);

    try minify(src, &w.interface, .{
        .src = src,
        .gpa = init.gpa,
        .io = init.io,
        .src_path = fname_in,
        .src_dir = cwd,
    });
    try w.flush();
}

pub const MinifyArgs = struct {
    /// Raw source code
    src: []const u8,

    /// Path of the source code
    src_path: ?[]const u8 = null,

    /// File lookups happen from here
    src_dir: ?std.Io.Dir = null,

    io: ?std.Io = null,
    gpa: std.mem.Allocator,
};

pub fn minify(src: []const u8, w: *std.Io.Writer, options: MinifyArgs) !void {
    var arena_alloc = std.heap.ArenaAllocator.init(options.gpa);
    defer arena_alloc.deinit();
    const arena = arena_alloc.allocator();

    const tokens = try tokenizer.tokenize(arena, &options);
    const nodes = try parser.parse(tokens, arena, &options);
    try optimizer.optimize(nodes, arena, &options);

    // Print AST, because I got nothin better to do
    try printer.print(nodes, w, src);
}
