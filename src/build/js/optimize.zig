pub const std = @import("std");

const ast = @import("ast.zig");
const Token = ast.Token;
const MinifyArgs = @import("../js_minify.zig").MinifyArgs;

const glsl_minify = @import("../glsl_minify.zig");

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
        .@"union" => |t| t.field_types[std.meta.fieldIndex(T, @tagName(field)).?],
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

            const decls = @typeInfo(glenum).@"struct".decl_names;
            var tuples: [decls.len]struct { []const u8, f64 } = undefined;

            for (decls, 0..) |decl, i| {
                tuples[i] = .{ decl, @field(glenum, decl) };
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
                    .number = .{ .custom = value },
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
            const fetch_ident: ast.Text = unionField(fetch_call.subject, .identifier) orelse return false;
            if (!std.mem.eql(u8, fetch_ident.toString(this.options.src), "fetch")) return false;

            // Ok...
            // Now find file
            const shader_fname_token: ast.Text = unionField(fetch_call.args[0], .string) orelse return false;
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

            // Try to minify shader source code
            var w = std.Io.Writer.Allocating.init(this.options.gpa);
            defer w.deinit();
            const shader_source = blk: {
                glsl_minify.minify(shader_file, &w.writer, .{
                    .gpa = this.options.gpa,
                    .src = shader_file,
                    .src_path = shader_fname,
                }) catch {
                    std.log.warn("shader minify failed for file '{s}', inlining raw file content instead", .{shader_path});
                    break :blk shader_file;
                };

                break :blk w.written();
            };

            // Ok, now inline it
            const inline_content = try std.mem.join(this.arena, "", &.{ "`", shader_source, "`" });
            node.* = .{ .string = .{ .custom = inline_content } };
            return true;
        }
    };

    const VarToArgument = struct {
        fn run(this: *Optimizer, node: *ast.Expression) bool {
            const arrow_fn = unionField(node, .arrow_fn) orelse return false;
            _ = this;
            _ = arrow_fn;
            return false;
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
};

pub fn optimize(nodes: []ast.Statement, arena: std.mem.Allocator, options: *const MinifyArgs) !void {
    const Context = struct {
        const Context = @This();

        o: Optimizer,

        fn statement(this: *Context, stmnt: *ast.Statement) ast.WalkResult {
            _ = this;
            _ = stmnt;
            return .repeat;
        }

        fn expression(this: *Context, expr: *ast.Expression) ast.WalkResult {
            // Try all optimizations on this node
            this.o.applyOptExpression(expr) catch |err| std.debug.panic("{}", .{err});
            return .repeat;
        }
    };
    var context = Context{ .o = .{
        .arena = arena,
        .options = options,
    } };

    var nodes_wrapped: [1]ast.Statement = .{ast.Statement{ .block = .{ .children = nodes } }};
    ast.walk(&nodes_wrapped, &context, .{
        .statement = Context.statement,
        .expression = Context.expression,
    });
}
