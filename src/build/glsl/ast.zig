const std = @import("std");

pub const Token = @import("tokenizer.zig").Token;

pub const Type = struct {
    precision: ?Token.Kind,
    name: Token,
};

pub const TopDecl = union(enum) {
    directive: Token,
    function: Function,
    var_decl: VarDecl,
    precision: PrecisionSpec,
};

pub const PrecisionSpec = struct {
    precision: Token.Kind,
    name: Token,
};

pub const Function = struct {
    return_type: Type,
    name: Token,
    parameters: []Parameter,
    body: BlockStmnt,

    pub const Parameter = struct {
        direction: Token.Kind = .in,
        type: Type,
        name: Token,
        array_members: []Expression,
    };
};

pub const VarDecl = struct {
    location: ?Token,
    interpolation_qualifier: ?Token.Kind,
    storage_qualifier: ?Token.Kind,
    type: Type,
    name: Token,
    array_members: []Expression,
    value: ?*Expression,
};

pub const Expression = union(enum) {
    // These ones are injected in the optimization step
    number_custom: f64,
    identifier_custom: []const u8,

    // These ones are all read from the source files
    number: Token,
    identifier: Token,
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
    field: Token,
};

pub const Statement = union(enum) {
    directive: Token,
    directive_custom: []const u8,

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
