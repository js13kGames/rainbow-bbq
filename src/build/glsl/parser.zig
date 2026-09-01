const std = @import("std");

const ast = @import("ast.zig");
const Token = ast.Token;
const MinifyArgs = @import("../glsl_minify.zig").MinifyArgs;

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
    tokens: []const Token,
    i: usize,
    options: *const MinifyArgs,

    fn nextTokenExpect(this: *Parser, kind: Token.Kind) Error!Token {
        const token = this.nextToken().?;
        if (token.kind != kind) {
            const line, const col = getFilePos(token.start, this.options.src);
            if (this.options.src_path) |fname| {
                std.log.debug("{s} L{d},C{d}: token of type {} did not match expected {}", .{ fname, line, col, token.kind, kind });
            } else {
                std.log.debug("L{d},C{d}: token of type {} did not match expected {}", .{ line, col, token.kind, kind });
            }
            return Error.SyntaxError;
        }

        return token;
    }

    fn nextExpect(this: *Parser, kind: Token.Kind) Error!void {
        const token = this.nextToken().?;
        if (token.kind != kind) {
            const line, const col = getFilePos(token.start, this.options.src);
            if (this.options.src_path) |fname| {
                std.log.err("{s} L{d},C{d}: token of type {} did not match expected {}", .{ fname, line, col, token.kind, kind });
            } else {
                std.log.err("L{d},C{d}: token of type {} did not match expected {}", .{ line, col, token.kind, kind });
            }
            return Error.SyntaxError;
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

    fn parseTopDecl(this: *Parser) Error!?ast.TopDecl {
        const token = this.peekToken() orelse return null;
        return switch (token.kind) {
            .directive => .{ .directive = try this.nextTokenExpect(.directive) },
            .uniform, .in, .out, .flat, .smooth, .@"const", .layout => .{ .var_decl = try this.parseVarDecl() },
            .lowp, .mediump, .highp, .identifier => try this.parseVarOrFunction(),
            .precision => try this.parsePrecisionSpec(),

            else => |kind| {
                std.log.err("unimplemented for top-decl: {}", .{kind});
                return Error.Unimplemented;
            },
        };
    }

    fn parseStatement(this: *Parser) Error!ast.Statement {
        const token = this.peekToken() orelse return Error.SyntaxError;
        return switch (token.kind) {
            .curly_open => try this.parseStmntBlock(),
            .@"if" => try this.parseStmntIf(),
            .lowp, .mediump, .highp, .@"const" => .{ .var_decl = try this.parseVarDecl() },
            .identifier => {
                const i = this.i;
                _ = try this.nextTokenExpect(.identifier);
                if (this.nextMaybe(.identifier)) |_| {
                    this.i = i;
                    return .{ .var_decl = try this.parseVarDecl() };
                } else {
                    this.i = i;
                    const expr = try this.parseExpression();
                    try this.nextExpect(.semicolon);
                    return .{ .expression = expr };
                }
            },

            // Must've been an expression then!
            else => {
                const expr = try this.parseExpression();
                try this.nextExpect(.semicolon);
                return .{ .expression = expr };
            },
        };
    }

    fn parseExpression(this: *Parser) Error!ast.Expression {
        var node: ast.Expression = switch (this.peekToken().?.kind) {
            .paren_open => try this.parseWrappedExpr(),
            .identifier => .{ .identifier = try this.nextTokenExpect(.identifier) },
            .number => .{ .number = try this.nextTokenExpect(.number) },
            .not, .neg, .minus, .plus, .increment, .decrement => try this.parseExprUnary(),

            else => |kind| {
                std.log.err("unimplemented for expression: {}", .{kind});
                return Error.Unimplemented;
            },
        };

        // Try and expand expression
        while (true) {
            const next = this.peekToken() orelse return node;
            node = switch (next.kind) {
                .dot => try this.parseExprDot(node),
                .paren_open => try this.parseExprCall(node),
                .increment, .decrement => try this.parseExprSuffix(node),
                .square_open => try this.parseExprIndex(node),
                .plus, .minus, .asterisk, .slash, .mod, .or_bin, .or_bool, .and_bin, .and_bool, .xor_bin, .shift_left, .shift_right, .compare, .compare_not, .angle_open, .angle_close, .less_or_equal, .greater_or_equal => try this.parseExprBinary(node),
                .equals, .plus_eq, .minus_eq, .asterisk_eq, .slash_eq, .mod_eq, .and_eq => try this.parseExprAssign(node),

                else => break,
            };

            // correctPrecedence(&node);
        }

        return node;
    }

    fn parseVarOrFunction(this: *Parser) Error!ast.TopDecl {
        const i = this.i;

        // Always start with a return/variable type and var/fn name
        _ = try this.parseType();
        try this.nextExpect(.identifier);

        // Ok, NOW what?
        const next_kind = this.nextToken().?.kind;
        this.i = i;
        return switch (next_kind) {
            .paren_open => try this.parseFunction(),
            .equals, .semicolon, .square_open => .{ .var_decl = try this.parseVarDecl() },
            else => Error.SyntaxError,
        };
    }

    fn parsePrecisionSpec(this: *Parser) Error!ast.TopDecl {
        try this.nextExpect(.precision);

        const precision = switch (this.nextToken().?.kind) {
            .lowp, .mediump, .highp => |kind| kind,
            else => return Error.SyntaxError,
        };

        const name = try this.nextTokenExpect(.identifier);
        try this.nextExpect(.semicolon);

        return .{ .precision = .{
            .precision = precision,
            .name = name,
        } };
    }

    fn parseFunction(this: *Parser) Error!ast.TopDecl {
        const return_type = try this.parseType();
        const name = try this.nextTokenExpect(.identifier);

        // Parameter list
        try this.nextExpect(.paren_open);
        var params = std.ArrayList(ast.Function.Parameter).empty;
        defer params.deinit(this.options.gpa);
        while (true) {
            if (this.nextMaybe(.paren_close)) |_| break;
            const param = try this.parseFunctionParameter();
            try params.append(this.options.gpa, param);

            if (this.nextMaybe(.paren_close)) |_| break;
            try this.nextExpect(.comma);
        }

        return .{
            .function = .{
                .return_type = return_type,
                .name = name,
                .parameters = try this.arena.dupe(ast.Function.Parameter, params.items),
                .body = (try this.parseStmntBlock()).block,
            },
        };
    }

    fn parseFunctionParameter(this: *Parser) Error!ast.Function.Parameter {
        const direction: Token.Kind = blk: {
            if (this.nextMaybe(.in)) |_| break :blk .in;
            if (this.nextMaybe(.out)) |_| break :blk .out;
            if (this.nextMaybe(.inout)) |_| break :blk .inout;
            break :blk .in;
        };

        const param_type = try this.parseType();
        const param_name = try this.nextTokenExpect(.identifier);

        // Are you an array??? Why is C-style syntax like this????
        var array_members: std.ArrayList(ast.Expression) = .empty;
        defer array_members.deinit(this.options.gpa);
        while (this.nextMaybe(.square_open)) |_| {
            const expr = try this.parseExpression();
            try array_members.append(this.options.gpa, expr);
            try this.nextExpect(.square_close);
        }

        return .{
            .direction = direction,
            .type = param_type,
            .name = param_name,
            .array_members = try this.arena.dupe(ast.Expression, array_members.items),
        };
    }

    fn parseVarDecl(this: *Parser) Error!ast.VarDecl {
        var location: ?Token = null;
        var interpolation: ?Token.Kind = null;
        var storage: ?Token.Kind = null;
        var array_members: std.ArrayList(ast.Expression) = .empty;
        defer array_members.deinit(this.options.gpa);

        switch (this.peekToken().?.kind) {
            else => {},
            .layout => {
                try this.nextExpect(.layout);
                try this.nextExpect(.paren_open);
                try this.nextExpect(.location);
                try this.nextExpect(.equals);
                location = try this.nextTokenExpect(.number);
                try this.nextExpect(.paren_close);
            },
        }
        switch (this.peekToken().?.kind) {
            else => {},
            .smooth, .flat => |kind| {
                interpolation = kind;
                this.i += 1;
            },
        }
        switch (this.peekToken().?.kind) {
            else => {},
            .@"const", .in, .out, .uniform => |kind| {
                storage = kind;
                this.i += 1;
            },
        }

        const var_type = try this.parseType();
        const var_name = try this.nextTokenExpect(.identifier);

        // Are you an array??? Why is C-style syntax like this????
        while (this.nextMaybe(.square_open)) |_| {
            const expr = try this.parseExpression();
            try array_members.append(this.options.gpa, expr);
            try this.nextExpect(.square_close);
        }

        var var_value: ?*ast.Expression = null;
        if (this.nextMaybe(.equals)) |_| {
            var_value = try this.allocNode(try this.parseExpression());
        }

        try this.nextExpect(.semicolon);

        return .{
            .location = location,
            .interpolation_qualifier = interpolation,
            .storage_qualifier = storage,
            .type = var_type,
            .name = var_name,
            .array_members = try this.arena.dupe(ast.Expression, array_members.items),
            .value = var_value,
        };
    }

    fn parseType(this: *Parser) Error!ast.Type {
        var precision: ?Token.Kind = null;
        switch (this.peekToken().?.kind) {
            else => {},
            .lowp, .mediump, .highp => |kind| {
                precision = kind;
                this.i += 1;
            },
        }

        return .{
            .precision = precision,
            .name = try this.nextTokenExpect(.identifier),
        };
    }

    fn parseExprBinary(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        const op = switch (this.nextToken().?.kind) {
            .plus, .minus, .asterisk, .slash, .mod, .or_bin, .or_bool, .and_bin, .and_bool, .xor_bin, .shift_left, .shift_right, .compare, .compare_not, .angle_open, .angle_close, .less_or_equal, .greater_or_equal => |kind| kind,
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
            .equals, .plus_eq, .minus_eq, .asterisk_eq, .slash_eq, .mod_eq, .and_eq, .or_eq => |kind| kind,
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
        try this.nextExpect(.square_open);
        const index = try this.parseExpression();
        try this.nextExpect(.square_close);

        return .{ .index = .{
            .subject = try this.allocNode(previous),
            .index = try this.allocNode(index),
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

    fn parseExprUnary(this: *Parser) Error!ast.Expression {
        const operation = switch (this.nextToken().?.kind) {
            .not, .neg, .minus, .plus, .increment, .decrement => |kind| kind,
            else => return error.SyntaxError,
        };

        const expr = try this.parseExpression();

        return .{ .unary = .{
            .op = operation,
            .subject = try this.allocNode(expr),
        } };
    }

    fn parseStmntIf(this: *Parser) Error!ast.Statement {
        try this.nextExpect(.@"if");
        try this.nextExpect(.paren_open);
        const condition = try this.parseExpression();
        try this.nextExpect(.paren_close);
        const consequent = try this.parseStatement();
        const alternate = if (this.nextMaybe(.@"else")) |_| try this.parseStatement() else null;

        return .{ .@"if" = .{
            .condition = try this.allocNode(condition),
            .consequent = try this.allocNode(consequent),
            .alternate = if (alternate) |a| try this.allocNode(a) else null,
        } };
    }

    fn parseExprCall(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        try this.nextExpect(.paren_open);

        // Read arguments
        var args = std.ArrayList(ast.Expression).empty;
        defer args.deinit(this.options.gpa);

        while (true) {
            if (this.nextIs(.paren_close)) break;

            const arg = try this.parseExpression();
            try args.append(this.options.gpa, arg);

            if (this.nextIs(.paren_close)) break;
            try this.nextExpect(.comma);
        }

        try this.nextExpect(.paren_close);

        return .{ .call = .{
            .subject = try this.allocNode(previous),
            .args = try this.arena.dupe(ast.Expression, args.items),
        } };
    }

    fn parseExprDot(this: *Parser, previous: ast.Expression) Error!ast.Expression {
        try this.nextExpect(.dot);

        const field_name = try this.nextTokenExpect(.identifier);

        return .{
            .dot = .{
                .subject = try this.allocNode(previous),
                .field = field_name,
            },
        };
    }

    fn parseStmntBlock(this: *Parser) Error!ast.Statement {
        var children = std.ArrayList(ast.Statement).empty;
        defer children.deinit(this.options.gpa);

        try this.nextExpect(.curly_open);

        while (true) {
            if (this.nextIs(.curly_close)) {
                this.i += 1;
                break;
            }

            try children.append(this.options.gpa, try this.parseStatement());
        }

        return .{ .block = .{
            .children = try this.arena.dupe(ast.Statement, children.items),
        } };
    }

    fn parseWrappedExpr(this: *Parser) Error!ast.Expression {
        try this.nextExpect(.paren_open);
        const expr = try this.parseExpression();
        try this.nextExpect(.paren_close);
        return .{ .wrapped = try this.allocNode(expr) };
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
pub fn parse(tokens: []const Token, arena: std.mem.Allocator, options: *const MinifyArgs) ![]ast.TopDecl {
    var p = Parser{
        .arena = arena,
        .i = 0,
        .tokens = tokens,
        .options = options,
    };

    // Parse body
    var nodes = std.ArrayList(ast.TopDecl).empty;
    defer nodes.deinit(p.options.gpa);

    while (try p.parseTopDecl()) |top_decl| {
        try nodes.append(p.options.gpa, top_decl);
    }

    return try p.arena.dupe(ast.TopDecl, nodes.items);
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
