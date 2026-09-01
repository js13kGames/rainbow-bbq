const std = @import("std");

const tokenizer = @import("tokenizer.zig");
const Token = tokenizer.Token;
const ast = @import("ast.zig");
const MinifyArgs = @import("../js_minify.zig").MinifyArgs;

const Error = error{
    OutOfMemory,
    Unimplemented,
    SyntaxError,
};

fn getFilePos(index: usize, source: []const u8) struct { u32, u32 } {
    var line: u32 = 1;
    var col: u32 = 1;

    for (source[0..index]) |char| {
        if (char == '\n') {
            line += 1;
            col = 1;
        } else {
            col += 1;
        }
    }

    return .{ line, col };
}

const Parser = struct {
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    tokens: []const Token,
    i: usize,
    src: []const u8,

    fn nextTokenExpect(this: *Parser, kind: Token.Kind) Token {
        const token = this.nextToken().?;
        if (token.kind != kind) {
            const line, const col = getFilePos(token.start, this.src);
            std.debug.panic("L{d},C{d}: token of type {} did not match expected {}", .{ line, col, token.kind, kind });
        }

        return token;
    }

    fn nextExpect(this: *Parser, kind: Token.Kind) void {
        const token = this.nextToken().?;
        if (token.kind != kind) {
            const line, const col = getFilePos(token.start, this.src);
            std.debug.panic("L{d},C{d}: token of type {} did not match expected {}", .{ line, col, token.kind, kind });
        }
    }

    fn eof(this: *Parser) bool {
        return this.i >= this.tokens.len;
    }

    fn nextToken(this: *Parser) ?Token {
        if (this.eof()) return null;
        const token = this.tokens[this.i];
        this.i += 1;
        return token;
    }

    fn peekToken(this: *Parser) ?Token {
        if (this.eof()) return null;
        return this.tokens[this.i];
    }

    fn nextIs(this: *Parser, kind: Token.Kind) bool {
        const token = this.peekToken() orelse return false;
        return token.kind == kind;
    }

    fn nextMaybe(this: *Parser, kind: Token.Kind) ?Token {
        return if (this.nextIs(kind)) this.nextToken() else null;
    }

    fn parseStatement(this: *Parser) Error!?ast.Statement {
        const token = this.peekToken() orelse return null;
        return switch (token.kind) {
            .curly_open => try this.parseStmntBlock(),
            .@"const", .let, .@"var" => try this.parseStmntVar(),
            .@"if" => try this.parseStmntIf(),
            .throw => try this.parseStmntThrow(),
            .@"try" => try this.parseStmntTry(),

            // Must've been an expression then!
            else => blk: {
                const expr = try this.parseExpression();
                this.nextExpect(.semicolon);
                break :blk .{ .expression = expr };
            },
        };
    }

    fn parseExpression(this: *Parser) Error!ast.Expression {
        var node: ast.Expression = switch (this.peekToken().?.kind) {
            .paren_open => try this.parseParensExpr(),
            .async => try this.parseArrowFn(),
            .identifier => .{ .identifier = this.nextTokenExpect(.identifier) },
            .string => .{ .string = this.nextTokenExpect(.string) },
            .number => .{ .number = this.nextTokenExpect(.number) },
            .not, .neg, .minus, .await, .plus, .new, .increment, .decrement => try this.parseExprUnary(),
            .curly_open => try this.parseExprObject(),
            .square_open => try this.parseExprArray(),

            else => |kind| {
                std.log.err("unimplemented for expression: {}", .{kind});
                return Error.Unimplemented;
            },
        };

        // Try and expand expression
        while (true) {
            const next = this.peekToken() orelse return node;
            node = switch (next.kind) {
                .dot, .dot_nullish, .dot_private => try this.parseExprDot(node),
                .paren_open => try this.parseExprCall(node),
                .increment, .decrement => try this.parseExprSuffix(node),
                .square_open => try this.parseExprIndex(node),
                .plus, .minus, .asterisk, .slash, .or_bin, .or_bool, .and_bin, .and_bool, .xor_bin, .shift_left, .shift_right_s, .shift_right_u, .compare_loose, .compare_strict, .compare_not_loose, .compare_not_strict, .angle_open, .angle_close, .less_or_equal, .greater_or_equal, .exponent => try this.parseExprBinary(node),
                .equals, .plus_eq, .minus_eq, .asterisk_eq, .slash_eq, .and_eq => try this.parseExprAssign(node),

                else => break,
            };

            // correctPrecedence(&node);
        }

        return node;
    }

    fn parseExprBinary(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        const op = switch (this.nextToken().?.kind) {
            .plus, .minus, .asterisk, .slash, .or_bin, .or_bool, .and_bin, .and_bool, .xor_bin, .shift_left, .shift_right_s, .shift_right_u, .compare_loose, .compare_strict, .compare_not_loose, .compare_not_strict, .angle_open, .angle_close, .less_or_equal, .greater_or_equal, .exponent => |kind| kind,
            else => return Error.SyntaxError,
        };

        const expr = try this.parseExpression();

        return .{ .binary = .{
            .op = op,
            .left = try this.allocNode(previous),
            .right = try this.allocNode(expr),
        } };
    }

    fn parseExprAssign(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        const op = switch (this.nextToken().?.kind) {
            .equals, .plus_eq, .minus_eq, .asterisk_eq, .slash_eq, .and_eq => |kind| kind,
            else => return Error.SyntaxError,
        };

        const expr = try this.parseExpression();

        return .{ .assign = .{
            .op = op,
            .left = try this.allocNode(previous),
            .right = try this.allocNode(expr),
        } };
    }

    fn parseExprIndex(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        this.nextExpect(.square_open);
        const index = try this.parseExpression();
        this.nextExpect(.square_close);

        return .{ .index = .{
            .subject = try this.allocNode(previous),
            .index = try this.allocNode(index),
        } };
    }

    fn parseExprArray(this: *Parser) Error!ast.Expression {
        var values = std.ArrayList(ast.Expression).empty;
        defer values.deinit(this.gpa);

        this.nextExpect(.square_open);
        while (true) {
            if (this.nextMaybe(.square_close)) |_| break;

            const value = try this.parseExpression();
            try values.append(this.gpa, value);

            if (this.nextMaybe(.square_close)) |_| break;
            this.nextExpect(.comma);
        }

        return .{ .array = .{
            .values = try this.arena.dupe(ast.Expression, values.items),
        } };
    }

    fn parseExprObject(this: *Parser) Error!ast.Expression {
        var entries = std.ArrayList(ast.ObjectLiteral.Entry).empty;
        defer entries.deinit(this.gpa);

        this.nextExpect(.curly_open);
        while (true) {
            if (this.nextMaybe(.curly_close)) |_| break;

            const next = this.nextToken().?;
            const key: ast.ObjectLiteral.Key = switch (next.kind) {
                .string => .{ .string = next },
                .number => .{ .number = next },
                .identifier => .{ .identifier = next },
                .square_open => blk: {
                    const expr = try this.parseExpression();
                    this.nextExpect(.square_close);
                    break :blk .{ .expression = try this.allocNode(expr) };
                },
                else => return Error.SyntaxError,
            };

            this.nextExpect(.colon);
            const value = try this.parseExpression();

            try entries.append(this.gpa, .{
                .key = key,
                .value = try this.allocNode(value),
            });

            if (this.nextMaybe(.curly_close)) |_| break;
            this.nextExpect(.comma);
        }

        return .{ .object = .{
            .entries = try this.arena.dupe(ast.ObjectLiteral.Entry, entries.items),
        } };
    }

    fn parseExprSuffix(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        const operation = switch (this.nextToken().?.kind) {
            .increment, .decrement => |kind| kind,
            else => return error.SyntaxError,
        };

        return .{ .suffix = .{
            .op = operation,
            .subject = try this.allocNode(previous),
        } };
    }

    fn parseStmntThrow(this: *Parser) Error!ast.Statement {
        this.nextExpect(.throw);
        const expr = try this.parseExpression();
        this.nextExpect(.semicolon);

        return .{ .throw = .{
            .subject = try this.allocNode(expr),
        } };
    }

    fn parseExprUnary(this: *Parser) Error!ast.Expression {
        const operation = switch (this.nextToken().?.kind) {
            .not, .neg, .minus, .await, .plus, .new, .increment, .decrement => |kind| kind,
            else => return error.SyntaxError,
        };

        const expr = try this.parseExpression();

        return .{ .unary = .{
            .op = operation,
            .subject = try this.allocNode(expr),
        } };
    }

    fn parseStmntTry(this: *Parser) Error!ast.Statement {
        this.nextExpect(.@"try");
        const try_block = (try this.parseStmntBlock()).block;

        var catch_block: ?ast.TryStmnt.CatchBlock = null;
        if (this.nextMaybe(.@"catch")) |_| {
            var capture: ?ast.Token = null;
            if (this.nextMaybe(.paren_open)) |_| {
                capture = this.nextTokenExpect(.identifier);
                this.nextExpect(.paren_close);
            }

            catch_block = .{
                .capture = capture,
                .block = (try this.parseStmntBlock()).block,
            };
        }

        var finally_block: ?ast.BlockStmnt = null;
        if (this.nextMaybe(.finally)) |_| {
            finally_block = (try this.parseStmntBlock()).block;
        }

        return .{ .@"try" = .{
            .@"try" = try_block,
            .@"catch" = catch_block,
            .finally = finally_block,
        } };
    }

    fn parseStmntIf(this: *Parser) Error!ast.Statement {
        this.nextExpect(.@"if");
        this.nextExpect(.paren_open);
        const condition = try this.parseExpression();
        this.nextExpect(.paren_close);
        const consequent = (try this.parseStatement()).?;
        const alternate = if (this.nextMaybe(.@"else")) |_| (try this.parseStatement()).? else null;

        return .{ .@"if" = .{
            .condition = try this.allocNode(condition),
            .consequent = try this.allocNode(consequent),
            .alternate = if (alternate) |a| try this.allocNode(a) else null,
        } };
    }

    fn parseExprCall(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        this.nextExpect(.paren_open);

        // Read arguments
        var args = std.ArrayList(ast.Expression).empty;
        defer args.deinit(this.gpa);

        while (true) {
            if (this.nextIs(.paren_close)) break;

            const arg = try this.parseExpression();
            try args.append(this.gpa, arg);

            if (!this.nextIs(.comma)) break;
            this.nextExpect(.comma);
        }

        this.nextExpect(.paren_close);

        return .{ .call = .{
            .subject = try this.allocNode(previous),
            .args = try this.arena.dupe(ast.Expression, args.items),
        } };
    }

    fn parseExprDot(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        const access_type = switch (this.nextToken().?.kind) {
            .dot, .dot_nullish, .dot_private => |val| val,
            else => return error.SyntaxError,
        };

        const field_name = this.nextTokenExpect(.identifier);

        return .{
            .dot = .{
                .subject = try this.allocNode(previous),
                .dot_type = access_type,
                .field = field_name,
            },
        };
    }

    fn parseStmntVar(this: *Parser) Error!ast.Statement {
        const decl_type = switch (this.nextToken().?.kind) {
            .@"var", .let, .@"const" => |val| val,
            else => return error.SyntaxError,
        };

        const name = this.nextTokenExpect(.identifier);

        var default_value: ?*ast.Expression = null;
        if (this.nextMaybe(.equals)) |_| {
            default_value = try this.allocNode(try this.parseExpression());
        }

        this.nextExpect(.semicolon);
        return .{ .@"var" = .{
            .decl_type = decl_type,
            .name = name,
            .value = default_value,
        } };
    }

    fn parseStmntBlock(this: *Parser) Error!ast.Statement {
        var children = std.ArrayList(ast.Statement).empty;
        defer children.deinit(this.gpa);

        this.nextExpect(.curly_open);

        while (true) {
            if (this.nextIs(.curly_close)) {
                this.i += 1;
                break;
            }

            try children.append(this.gpa, (try this.parseStatement()).?);
        }

        return .{ .block = .{
            .children = try this.arena.dupe(ast.Statement, children.items),
        } };
    }

    fn parseParensExpr(this: *Parser) Error!ast.Expression {
        const paren_start = this.i;
        this.nextExpect(.paren_open);

        // Skip forward until we find the end of the parentheses
        var opened: usize = 1;
        while (opened != 0) {
            const next = this.nextToken().?;
            switch (next.kind) {
                .paren_open => opened += 1,
                .paren_close => opened -= 1,
                else => {},
            }
        }

        // Alright, now what?
        const next_o = this.nextToken();
        this.i = paren_start;
        const next = next_o orelse {
            return try this.parseWrappedExpr();
        };

        if (next.kind == .arrow) {
            return try this.parseArrowFn();
        } else {
            return try this.parseWrappedExpr();
        }
    }

    fn parseWrappedExpr(this: *Parser) Error!ast.Expression {
        this.nextExpect(.paren_open);
        const expr = try this.parseExpression();
        this.nextExpect(.paren_close);
        return .{ .wrapped = try this.allocNode(expr) };
    }

    fn parseArrowFn(this: *Parser) Error!ast.Expression {
        var async = false;
        if (this.nextIs(.async)) {
            async = true;
            this.i += 1;
        }

        // Read argument list
        var args = std.ArrayList(ast.FnParam).empty;
        defer args.deinit(this.gpa);

        this.nextExpect(.paren_open);
        while (true) {
            const next = this.peekToken().?;
            if (next.kind == .paren_close) {
                break;
            }

            const name = this.nextTokenExpect(.identifier);
            var default_value: ?*ast.Expression = null;
            if (this.nextIs(.equals)) {
                this.nextExpect(.equals);
                default_value = try this.arena.create(ast.Expression);
                default_value.?.* = try this.parseExpression();
            }

            try args.append(this.gpa, .{
                .name = name,
                .default_value = default_value,
            });

            if (this.nextIs(.paren_close)) {
                break;
            }
            this.nextExpect(.comma);
        }
        this.nextExpect(.paren_close);

        this.nextExpect(.arrow);

        // Parse body
        return .{ .arrow_fn = .{
            .async = async,
            .params = try this.arena.dupe(ast.FnParam, args.items),
            .body = switch (this.peekToken().?.kind) {
                .curly_open => .{ .block = try this.allocNode((try this.parseStmntBlock()).block) },
                else => .{ .expression = try this.allocNode(try this.parseExpression()) },
            },
        } };
    }

    pub fn allocNode(this: *Parser, node: anytype) !*@TypeOf(node) {
        const node_mem = try this.arena.create(@TypeOf(node));
        node_mem.* = node;
        return node_mem;
    }
};

/// All nodes are allocated in an arena
/// GPA is used for scratch space.
/// All returned nodes will be located in the arena.
pub fn parse(tokens: []const Token, arena: std.mem.Allocator, options: *const MinifyArgs) ![]ast.Statement {
    var p = Parser{
        .arena = arena,
        .gpa = options.gpa,
        .i = 0,
        .tokens = tokens,
        .src = options.src,
    };

    // Parse body
    var children = std.ArrayList(ast.Statement).empty;
    defer children.deinit(p.gpa);

    while (try p.parseStatement()) |statement| {
        try children.append(p.gpa, statement);
    }

    return try p.arena.dupe(ast.Statement, children.items);
}

pub fn correctPrecedence(expr: *ast.Expression) void {
    const prec_self = expr.getPrecedence() orelse return;

    switch (expr.*) {
        .binary => |node| {
            const prec_prev = node.left.getPrecedence() orelse return;
            if (prec_prev >= prec_self) return;

            const on_stack = expr;
            const on_heap = node.left;

            // Switch them in memory
            const temp = on_stack.*;
            on_stack.* = on_heap.*;
            on_heap.* = temp;

            // Modify them
            on_heap.binary.left = swapPrec(on_stack, on_heap);
        },

        else => std.debug.panic("no", .{}),
    }
}

fn swapPrec(expr: *ast.Expression, swap_in: *ast.Expression) *ast.Expression {
    switch (expr.*) {
        .binary => |*bin| {
            const swap_out = bin.right;
            bin.right = swap_in;
            return swap_out;
        },

        else => std.debug.panic("no", .{}),
    }
}

test "precedence swap, bin - bin" {
    var expr_1 = ast.Expression{ .number = .{ .kind = .number, .start = 0, .end = 1 } };
    var expr_2 = ast.Expression{ .number = .{ .kind = .number, .start = 1, .end = 2 } };
    var expr_3 = ast.Expression{ .number = .{ .kind = .number, .start = 2, .end = 3 } };

    var expr_previous = ast.Expression{ .binary = .{
        .op = .plus,
        .left = &expr_1,
        .right = &expr_2,
    } };

    var expr_stack = ast.Expression{ .binary = .{
        .op = .asterisk,
        .left = &expr_previous,
        .right = &expr_3,
    } };

    correctPrecedence(&expr_stack);

    std.debug.assert(expr_stack.binary.op == .plus);
    std.debug.assert(expr_stack.binary.left == &expr_1);
    std.debug.assert(expr_stack.binary.right == &expr_previous);

    std.debug.assert(expr_previous.binary.op == .asterisk);
    std.debug.assert(expr_previous.binary.left == &expr_2);
    std.debug.assert(expr_previous.binary.right == &expr_3);
}
