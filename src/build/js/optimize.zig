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

    /// Only apply this one ONCE
    const MinifyNames = struct {
        const Name = struct {
            name: []const u8,
            usages: std.ArrayList(*ast.Text) = .empty,
        };

        const Scope = struct {
            node: *const anyopaque,
            seen_before: usize,
        };

        const Walker = struct {
            gpa: std.mem.Allocator,
            arena: std.mem.Allocator,
            src: []const u8,

            reserved_names: std.StringHashMap(void),
            names: std.ArrayList(Name) = .empty,
            blocks: std.ArrayList(Scope) = .empty,
            in_scope: std.ArrayList(usize) = .empty,

            fn findOrDeclare(this: *Walker, name: *ast.Text) *Name {
                if (this.findDecl(name)) |existing| {
                    return existing;
                }

                const slot = this.names.addOne(this.gpa) catch @panic("OOM");
                slot.* = .{
                    .name = name.toString(this.src),
                    .usages = std.ArrayList(*ast.Text).initCapacity(this.gpa, 4) catch @panic("OOM"),
                };

                this.in_scope.append(this.gpa, this.names.items.len - 1) catch @panic("OOM");
                return slot;
            }

            fn findDecl(this: *Walker, name: *ast.Text) ?*Name {
                const name_str = name.toString(this.src);

                for (this.in_scope.items) |i| {
                    const existing = &this.names.items[i];
                    if (std.mem.eql(u8, name_str, existing.name)) {
                        return existing;
                    }
                }

                return null;
            }

            fn pushScope(this: *Walker, val: *const anyopaque) void {
                this.blocks.append(this.gpa, .{
                    .node = val,
                    .seen_before = this.in_scope.items.len,
                }) catch @panic("OOM");
            }

            fn popScope(this: *Walker) void {
                const frame = this.blocks.pop().?;
                this.in_scope.items.len = frame.seen_before;
            }

            /// Returns true if scope was opened
            fn handleScope(this: *Walker, node: *const anyopaque) bool {
                const frame = this.blocks.last() orelse {
                    this.pushScope(node);
                    return true;
                };

                if (frame.node != node) {
                    this.pushScope(node);
                    return true;
                }

                // Popped block, yay!
                this.popScope();
                return false;
            }

            fn statement(this: *Walker, stmnt: *ast.Statement) ast.WalkResult {
                switch (stmnt.*) {
                    .block => {
                        _ = this.handleScope(stmnt);
                        return .repeat;
                    },

                    .@"var" => |*decl| {
                        const name = this.findOrDeclare(&decl.name);
                        name.usages.append(this.gpa, &decl.name) catch @panic("OOM");
                    },

                    // .@"try" => @panic("todo"),

                    else => {},
                }

                return .walk;
            }

            fn expression(this: *Walker, expr: *ast.Expression) ast.WalkResult {
                switch (expr.*) {
                    .identifier => |*node| {
                        if (this.findDecl(node)) |decl| {
                            decl.usages.append(this.gpa, node) catch @panic("OOM");
                        } else {
                            this.reserved_names.put(node.toString(this.src), {}) catch @panic("OOM");
                        }
                    },

                    .arrow_fn => |*node| {
                        if (this.handleScope(expr)) {
                            for (node.params) |*param| {
                                const param_name = this.findOrDeclare(&param.name);
                                param_name.usages.append(this.gpa, &param.name) catch @panic("OOM");
                            }
                            return .repeat;
                        }
                    },

                    else => {},
                }

                return .walk;
            }
        };

        const NameGenerator = struct {
            name_idx: usize = 0,
            reserved_names: std.StringHashMap(void),

            const charset_0 = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_$";
            const charset_n = charset_0 ++ "0123456789";

            fn generateName(name_idx: usize, buf: []u8) []const u8 {
                var i: usize = 0;
                var n: usize = name_idx;

                // Always emit first char
                {
                    const rem = n % charset_0.len;
                    n = n / charset_0.len;
                    buf[i] = charset_0[rem];
                    i += 1;
                }

                while (n != 0) {
                    const rem = n % charset_n.len;
                    n = n / charset_n.len;
                    buf[i] = charset_n[rem];
                    i += 1;
                }

                return buf[0..i];
            }

            fn generateUniqueName(this: *NameGenerator, buf: []u8) []const u8 {
                while (true) {
                    const name = generateName(this.name_idx, buf);
                    this.name_idx += 1;

                    if (!this.reserved_names.contains(name)) {
                        return name;
                    }
                }
            }
        };

        fn run(this: *Optimizer, nodes: []ast.Statement) !void {
            var context = Walker{
                .gpa = this.options.gpa,
                .arena = this.arena,
                .src = this.options.src,

                .reserved_names = .init(this.options.gpa),
            };

            defer {
                // Free everything
                for (context.names.items) |*name| name.usages.deinit(context.gpa);
                context.names.deinit(context.gpa);
                context.in_scope.deinit(context.gpa);
                context.blocks.deinit(context.gpa);
                context.reserved_names.deinit();
            }

            ast.walk(nodes, &context, .{
                .statement = Walker.statement,
                .expression = Walker.expression,
            });

            // Sort by number of usages
            // Sort cels
            std.sort.insertion(Name, context.names.items, {}, struct {
                fn inner(_: void, a: Name, b: Name) bool {
                    return a.usages.items.len > b.usages.items.len;
                }
            }.inner);

            var name_generator = NameGenerator{
                .reserved_names = context.reserved_names,
            };

            for (context.names.items) |name| {
                // Generate replacement name
                var buf: [64]u8 = undefined;
                const gen_name = name_generator.generateUniqueName(&buf);
                const gen_name_alloc = try this.arena.dupe(u8, gen_name);

                // Go and actually replace it
                for (name.usages.items) |text| {
                    text.* = .{ .custom = gen_name_alloc };
                }
            }
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

    // Aaaaand mangle names
    try Optimizer.MinifyNames.run(&context.o, &nodes_wrapped);
}
