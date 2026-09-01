pub const std = @import("std");

const ast = @import("ast.zig");
const Token = ast.Token;
const MinifyArgs = @import("../js_minify.zig").MinifyArgs;

/// Returns the union tag or null
fn unionField(node: anytype, comptime field: UnionTag(@TypeOf(node))) ?UnionField(@TypeOf(node), field) {
    const T = @TypeOf(node);
    return switch (@typeInfo(T)) {
        .pointer => unionField(node.*, field),
        .@"union" => if (std.meta.activeTag(node) == field) @field(node, @tagName(field)) else null,
        else => @compileError("type '" ++ @typeName(T) ++ "' is not a union"),
    };
}

fn UnionTag(T: type) type {
    return switch (@typeInfo(T)) {
        .pointer => |t| UnionTag(t.child),
        .@"union" => std.meta.Tag(T),
        else => @compileError("type '" ++ @typeName(T) ++ "' is not a union"),
    };
}

fn UnionField(T: type, comptime field: UnionTag(T)) type {
    return switch (@typeInfo(T)) {
        .pointer => |t| UnionField(t.child, field),
        .@"union" => |t| t.fields[std.meta.fieldIndex(T, @tagName(field)).?].type,
        else => @compileError("type '" ++ @typeName(T) ++ "' is not a union"),
    };
}

const Error = std.mem.Allocator.Error;

const Optimizer = struct {
    arena: std.mem.Allocator,
    options: *const MinifyArgs,

    const RemoveGlEnum = struct {
        const glenum_to_value = blk: {
            const glenum = @import("glenum.zig");

            const decls = @typeInfo(glenum).@"struct".decls;
            var tuples: [decls.len]struct { []const u8, f64 } = undefined;

            for (decls, 0..) |decl, i| {
                tuples[i] = .{ decl.name, @field(glenum, decl.name) };
            }

            const slice: []struct { []const u8, f64 } = &tuples;
            break :blk std.StaticStringMap(f64).initComptime(slice);
        };

        fn run(this: *Optimizer, node: *ast.Expression) bool {
            const dot: ast.DotExpr = unionField(node, .dot) orelse return false;

            // If this is a glenum value, scrap the entire expression
            const field_name = dot.field.toString(this.options.src);
            if (glenum_to_value.get(field_name)) |value| {
                node.* = .{
                    .number_custom = value,
                };
                return true;
            }

            return false;
        }
    };

    const StripWraps = struct {
        fn run(this: *Optimizer, node: *ast.Expression) bool {
            _ = this;
            const wrapped: *ast.Expression = unionField(node, .wrapped) orelse return false;
            node.* = wrapped.*;
            return true;
        }
    };

    const InlineShaderSource = struct {
        fn run(this: *Optimizer, node: *ast.Expression) Error!bool {
            const js_fname = this.options.src_path orelse return false;
            const io = this.options.io orelse return false;

            const await_text: ast.UnaryExpr = unionField(node, .unary) orelse return false;
            if (await_text.op != .await) return false;

            const text_call: ast.CallExpr = unionField(await_text.subject, .call) orelse return false;
            const text_dot: ast.DotExpr = unionField(text_call.subject, .dot) orelse return false;
            if (!std.mem.eql(u8, text_dot.field.toString(this.options.src), "text")) return false;

            const await_fetch: ast.UnaryExpr = unionField(text_dot.subject, .unary) orelse return false;
            if (await_fetch.op != .await) return false;

            const fetch_call: ast.CallExpr = unionField(await_fetch.subject, .call) orelse return false;
            const fetch_ident: Token = unionField(fetch_call.subject, .identifier) orelse return false;
            if (!std.mem.eql(u8, fetch_ident.toString(this.options.src), "fetch")) return false;

            // Ok...
            // Now find file
            const shader_fname_token: ast.Token = unionField(fetch_call.args[0], .string) orelse return false;
            const shader_fname = blk: {
                const token_str = shader_fname_token.toString(this.options.src);
                break :blk token_str[1 .. token_str.len - 1];
            };

            // Get shader path
            const shader_path = try std.Io.Dir.path.join(this.options.gpa, &.{
                std.Io.Dir.path.dirname(js_fname) orelse "",
                shader_fname,
            });
            defer this.options.gpa.free(shader_path);

            // Read shader file
            const dir = this.options.src_dir orelse std.Io.Dir.cwd();
            const shader_file = dir.readFileAlloc(io, shader_path, this.options.gpa, .unlimited) catch |err| switch (err) {
                Error.OutOfMemory => return Error.OutOfMemory,
                else => return false,
            };
            defer this.options.gpa.free(shader_file);

            // TODO: minify shader

            // Ok, now inline it
            const inline_content = try std.mem.join(this.arena, "", &.{ "`", shader_file, "`" });
            node.* = .{ .string_custom = inline_content };
            return true;
        }
    };

    fn applyOptExpression(this: *Optimizer, expr: *ast.Expression) Error!void {
        while (true) {
            var ran = false;
            ran = ran or StripWraps.run(this, expr);
            ran = ran or RemoveGlEnum.run(this, expr);
            ran = ran or try InlineShaderSource.run(this, expr);
            if (!ran) break;
        }
    }

    fn optimizeExpression(this: *Optimizer, expr: *ast.Expression) Error!void {
        // Try all optimizations on this node
        try this.applyOptExpression(expr);

        // Walk to child nodes
        switch (expr.*) {
            .identifier, .string, .number => {},
            .identifier_custom, .string_custom, .number_custom => {},
            .array => |node| {
                for (node.values) |*value| {
                    try this.optimizeExpression(value);
                }
            },
            .object => |node| {
                for (node.entries) |*entry| {
                    switch (entry.key) {
                        .expression => |key| try this.optimizeExpression(key),
                        else => {},
                    }
                    try this.optimizeExpression(entry.value);
                }
            },
            .unary => |node| try this.optimizeExpression(node.subject),
            .suffix => |node| try this.optimizeExpression(node.subject),
            .binary => |node| {
                try this.optimizeExpression(node.left);
                try this.optimizeExpression(node.right);
            },
            .index => |node| {
                try this.optimizeExpression(node.subject);
                try this.optimizeExpression(node.index);
            },
            .dot => |node| try this.optimizeExpression(node.subject),
            .call => |node| {
                try this.optimizeExpression(node.subject);
                for (node.args) |*arg| {
                    try this.optimizeExpression(arg);
                }
            },
            .arrow_fn => |node| {
                for (node.params) |param| {
                    if (param.default_value) |default_value| {
                        try this.optimizeExpression(default_value);
                    }
                }

                switch (node.body) {
                    .expression => |body| try this.optimizeExpression(body),
                    .block => |body| {
                        var tmp_block = ast.Statement{ .block = body.* };
                        try this.optimizeStatement(&tmp_block);
                        body.* = tmp_block.block;
                    },
                }
            },
            else => std.debug.panic("unimplemented: {}", .{std.meta.activeTag(expr.*)}),
        }

        // Try all optimizations on this node, AGAIN
        try this.applyOptExpression(expr);
    }

    fn optimizeStatement(this: *Optimizer, stmnt: *ast.Statement) Error!void {
        // Try all optimizations on this node

        // Walk to child nodes
        switch (stmnt.*) {
            .block => |*block| {
                for (block.children) |*child| {
                    try this.optimizeStatement(child);
                }
            },
            .expression => |*expr| try this.optimizeExpression(expr),
            .@"var" => |node| if (node.value) |value| try this.optimizeExpression(value),
            .throw => |node| try this.optimizeExpression(node.subject),
            .@"if" => |node| {
                try this.optimizeExpression(node.condition);
                try this.optimizeStatement(node.consequent);
                if (node.alternate) |alternate| try this.optimizeStatement(alternate);
            },
        }
    }
};

pub fn optimize(nodes: []ast.Statement, arena: std.mem.Allocator, options: *const MinifyArgs) !void {
    var o = Optimizer{
        .arena = arena,
        .options = options,
    };

    var block = ast.Statement{ .block = .{ .children = nodes } };
    try o.optimizeStatement(&block);
}
