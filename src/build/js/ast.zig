const std = @import("std");

pub const Token = @import("tokenizer.zig").Token;

pub const Text = union(enum) {
    src: Token,
    custom: []const u8,

    /// The returned string is either from the src array, or a const string.
    /// No need to free it.
    pub fn toString(this: Text, src: []const u8) []const u8 {
        return switch (this) {
            .src => |token| token.toString(src),
            .custom => |str| str,
        };
    }
};

pub const Number = union(enum) {
    src: Token,
    custom: f64,
};

pub const FnParam = struct {
    name: Text,
    default_value: ?*Expression,
};

pub const Expression = union(enum) {
    number: Number,
    string: Text,
    identifier: Text,
    object: ObjectLiteral,
    array: ArrayLiteral,
    arrow_fn: ArrowFn,
    dot: DotExpr,
    call: CallExpr,
    unary: UnaryExpr,
    suffix: SuffixExpr,
    index: IndexExpr,
    binary: BinaryExpression,
    assign: BinaryExpression,
    wrapped: *Expression,

    /// https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Operators/Operator_precedence
    pub fn getPrecedence(this: Expression) ?usize {
        return switch (this) {
            .wrapped => 18,
            .dot => 17,
            .call => 17,
            .index => 17,
            .suffix => 15,
            .unary => |un| switch (un.op) {
                .new => 17,
                .increment, .decrement, .not, .neg, .plus, .minus, .await => 14,
                .yield => 1,
                else => std.debug.panic("unreachable / unimplemented: {}", .{un.op}),
            },
            .binary => |bin| switch (bin.op) {
                .exponent => 13,
                .asterisk => 12,
                .slash => 12,
                .plus => 11,
                .minus => 11,
                .shift_left => 10,
                .shift_right_s => 10,
                .shift_right_u => 10,
                .angle_open => 9,
                .angle_close => 9,
                .greater_or_equal => 9,
                .less_or_equal => 9,
                .compare_strict, .compare_loose, .compare_not_strict, .compare_not_loose => 8,
                .and_bin => 7,
                .xor_bin => 6,
                .or_bin => 5,
                .and_bool => 4,
                .or_bool, .nullish => 3,
                else => std.debug.panic("unreachable / unimplemented: {}", .{bin.op}),
            },
            .arrow_fn => 2,
            else => null,
        };
    }
};

pub const IndexExpr = struct {
    subject: *Expression,
    index: *Expression,
};

pub const BinaryExpression = struct {
    op: Token.Kind,
    left: *Expression,
    right: *Expression,
};

pub const ArrayLiteral = struct {
    values: []Expression,
};

pub const ObjectLiteral = struct {
    entries: []Entry,

    pub const Key = union(enum) {
        identifier: Text,
        number: Text,
        string: Text,
        expression: *Expression,
    };

    pub const Entry = struct {
        key: Key,
        value: *Expression,
    };
};

pub const SuffixExpr = struct {
    op: Token.Kind,
    subject: *Expression,
};

pub const UnaryExpr = struct {
    op: Token.Kind,
    subject: *Expression,
};

pub const ArrowFn = struct {
    async: bool = false,
    params: []FnParam,
    body: union(enum) {
        block: *BlockStmnt,
        expression: *Expression,
    },
};

pub const CallExpr = struct {
    subject: *Expression,
    args: []Expression,
};

pub const DotExpr = struct {
    subject: *Expression,
    dot_type: Token.Kind,
    field: Text,
};

pub const Statement = union(enum) {
    block: BlockStmnt,
    expression: Expression,
    @"var": VarStmnt,
    @"if": IfStmnt,
    throw: ThrowStmnt,
    @"try": TryStmnt,
    @"return": ?Expression,
};

pub const BlockStmnt = struct {
    children: []Statement,
};

pub const VarStmnt = struct {
    decl_type: Token.Kind,
    name: Text,
    value: ?*Expression,
};

pub const IfStmnt = struct {
    condition: *Expression,
    consequent: *Statement,
    alternate: ?*Statement,
};

pub const ThrowStmnt = struct {
    subject: *Expression,
};

pub const TryStmnt = struct {
    pub const CatchBlock = struct {
        capture: ?Text,
        block: BlockStmnt,
    };

    @"try": BlockStmnt,
    @"catch": ?CatchBlock,
    finally: ?BlockStmnt,
};

pub const WalkResult = enum {
    /// Node will be walked
    walk,

    /// Callback will be called AGAIN after children have been walked
    repeat,

    /// If emitted, children of this node will not be walked
    skip,
};

pub fn Walker(comptime Context: type) type {
    return struct {
        const WalkerT = @This();

        pub const Options = struct {
            statement: ?*const fn (context: Context, stmnt: *Statement) WalkResult = null,
            expression: ?*const fn (context: Context, expr: *Expression) WalkResult = null,
        };

        context: Context,
        options: Options,

        fn statement(this: *const WalkerT, stmnt: *Statement) void {
            const repeat = if (this.options.statement) |walkFn| blk: {
                const result = walkFn(this.context, stmnt);
                break :blk switch (result) {
                    .skip => return,
                    .walk => false,
                    .repeat => true,
                };
            } else false;

            switch (stmnt.*) {
                .@"if" => |*node| {
                    this.expression(node.condition);
                    this.statement(node.consequent);
                    if (node.alternate) |alternate| this.statement(alternate);
                },

                .expression => |*node| {
                    this.expression(node);
                },

                .@"var" => |*node| {
                    if (node.value) |value| this.expression(value);
                },

                .block => |*node| {
                    for (node.children) |*child| {
                        this.statement(child);
                    }
                },

                .throw => |*node| {
                    this.expression(node.subject);
                },

                .@"try" => |*node| {
                    {
                        var block = Statement{ .block = node.@"try" };
                        this.statement(&block);
                        node.@"try" = block.block;
                    }

                    if (node.@"catch") |*node_c| {
                        var block = Statement{ .block = node_c.block };
                        this.statement(&block);
                        node_c.block = block.block;
                    }

                    if (node.finally) |*node_c| {
                        var block = Statement{ .block = node_c.* };
                        this.statement(&block);
                        node_c.* = block.block;
                    }
                },

                .@"return" => |*node| {
                    if (node.*) |*expr| {
                        this.expression(expr);
                    }
                },
            }

            if (repeat) {
                _ = this.options.statement.?(this.context, stmnt);
            }
        }

        fn expression(this: *const WalkerT, expr: *Expression) void {
            const repeat = if (this.options.expression) |walkFn| blk: {
                const result = walkFn(this.context, expr);
                break :blk switch (result) {
                    .skip => return,
                    .walk => false,
                    .repeat => true,
                };
            } else false;

            switch (expr.*) {
                .wrapped => |node| this.expression(node),

                .call => |*node| {
                    this.expression(node.subject);
                    for (node.args) |*arg| {
                        this.expression(arg);
                    }
                },

                .array => |*node| {
                    for (node.values) |*value| {
                        this.expression(value);
                    }
                },

                .arrow_fn => |*node| {
                    for (node.params) |*param| {
                        if (param.default_value) |value| {
                            this.expression(value);
                        }
                    }

                    switch (node.body) {
                        .block => |body| {
                            var block = Statement{ .block = body.* };
                            this.statement(&block);
                            node.body.block.* = block.block;
                        },
                        .expression => |body| this.expression(body),
                    }
                },

                .assign, .binary => |*node| {
                    this.expression(node.left);
                    this.expression(node.right);
                },

                .dot => |*node| this.expression(node.subject),

                .index => |*node| {
                    this.expression(node.subject);
                    this.expression(node.index);
                },

                .object => |*node| {
                    for (node.entries) |entry| {
                        switch (entry.key) {
                            .expression => |key| this.expression(key),
                            else => {},
                        }
                        this.expression(entry.value);
                    }
                },

                .suffix => |*node| this.expression(node.subject),
                .unary => |*node| this.expression(node.subject),

                .identifier => {},
                .number => {},
                .string => {},
            }

            if (repeat) {
                _ = this.options.expression.?(this.context, expr);
            }
        }
    };
}

pub fn walk(nodes: []Statement, context: anytype, options: Walker(@TypeOf(context)).Options) void {
    const Context = @TypeOf(context);

    var walker = Walker(Context){
        .context = context,
        .options = options,
    };

    for (nodes) |*node| {
        _ = walker.statement(node);
    }
}
