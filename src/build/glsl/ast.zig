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

pub const Type = struct {
    precision: ?Token.Kind,
    name: Text,
};

pub const TopDecl = union(enum) {
    directive: Text,
    function: Function,
    var_decl: VarDecl,
    precision: PrecisionSpec,
};

pub const PrecisionSpec = struct {
    precision: Token.Kind,
    name: Text,
};

pub const Function = struct {
    return_type: Type,
    name: Text,
    parameters: []Parameter,
    body: BlockStmnt,

    pub const Parameter = struct {
        direction: Token.Kind = .in,
        type: Type,
        name: Text,
        array_members: []Expression,
    };
};

pub const VarDecl = struct {
    location: ?Number,
    interpolation_qualifier: ?Token.Kind,
    storage_qualifier: ?Token.Kind,
    type: Type,
    name: Text,
    array_members: []Expression,
    value: ?*Expression,
};

pub const Expression = union(enum) {
    number: Number,
    identifier: Text,
    dot: DotExpr,
    call: CallExpr,
    unary: UnaryExpr,
    suffix: SuffixExpr,
    index: IndexExpr,
    binary: BinaryExpression,
    assign: BinaryExpression,
    wrapped: *Expression,

    /// https://registry.khronos.org/OpenGL/specs/es/3.0/GLSL_ES_Specification_3.00.pdf
    /// section 5.1
    pub fn getPrecedence(this: Expression) ?usize {
        return 17 - @as(usize, switch (this) {
            .wrapped => 1,
            .index => 2,
            .suffix => 2,
            .unary => 3,
            .binary => |bin| switch (bin.op) {
                .asterisk => 4,
                .slash => 4,
                .mod => 4,
                .plus => 5,
                .minus => 5,
                .shift_left => 6,
                .shift_right => 6,
                .angle_open => 7,
                .angle_close => 7,
                .less_or_equal => 7,
                .greater_or_equal => 7,
                .compare => 8,
                .compare_not => 8,
                .and_bin => 9,
                .xor_bin => 10,
                .or_bin => 11,
                .and_bool => 12,
                .or_bool => 14,
                else => unreachable,
            },
            .assign => 16,
            else => return null,
        });
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

pub const SuffixExpr = struct {
    op: Token.Kind,
    subject: *Expression,
};

pub const UnaryExpr = struct {
    op: Token.Kind,
    subject: *Expression,
};

pub const CallExpr = struct {
    subject: *Expression,
    args: []Expression,
};

pub const DotExpr = struct {
    subject: *Expression,
    field: Text,
};

pub const Statement = union(enum) {
    directive: Text,
    block: BlockStmnt,
    expression: Expression,
    @"if": IfStmnt,
    var_decl: VarDecl,
};

pub const BlockStmnt = struct {
    children: []Statement,
};

pub const IfStmnt = struct {
    condition: *Expression,
    consequent: *Statement,
    alternate: ?*Statement,
};
