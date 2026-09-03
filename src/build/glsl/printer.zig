const std = @import("std");

const ast = @import("ast.zig");
const Token = @import("tokenizer.zig").Token;

const Error = std.Io.Writer.Error;

const Printer = struct {
    w: *std.Io.Writer,
    src: []const u8,
    is_new_line: bool = true,

    fn printType(this: *Printer, node: ast.Type) Error!void {
        if (node.precision) |prec| {
            try this.w.writeAll(prec.toString());
            try this.w.writeByte(' ');
        }
        try this.w.writeAll(node.name.toString(this.src));
    }

    fn printVarDecl(this: *Printer, node: ast.VarDecl) Error!void {
        if (node.location) |location| {
            try this.w.writeAll("layout(location=");
            try this.printExpression(.{ .number = location }, null);
            try this.w.writeAll(")");
        }
        if (node.interpolation_qualifier) |qual| {
            try this.w.writeAll(qual.toString());
            try this.w.writeByte(' ');
        }
        if (node.storage_qualifier) |qual| {
            try this.w.writeAll(qual.toString());
            try this.w.writeByte(' ');
        }

        try this.printType(node.type);
        try this.w.writeByte(' ');
        try this.w.writeAll(node.name.toString(this.src));

        for (node.array_members) |arr_mem| {
            try this.w.writeByte('[');
            try this.printExpression(arr_mem, null);
            try this.w.writeByte(']');
        }

        if (node.value) |value| {
            try this.w.writeByte('=');
            try this.printExpression(value.*, null);
        }
        try this.w.writeByte(';');
    }

    fn printTopDecl(this: *Printer, top_decl: ast.TopDecl) Error!void {
        switch (top_decl) {
            .directive => |node| {
                // Directives must be on their own line
                if (!this.is_new_line) try this.w.writeByte('\n');
                try this.w.writeAll(node.toString(this.src));
                try this.w.writeByte('\n');
            },

            .function => |node| {
                try this.printType(node.return_type);
                try this.w.writeByte(' ');
                try this.w.writeAll(node.name.toString(this.src));

                try this.w.writeByte('(');
                for (node.parameters, 0..) |param, i| {
                    if (i != 0) try this.w.writeByte(',');

                    if (param.direction != .in) {
                        try this.w.writeAll(param.direction.toString());
                        try this.w.writeByte(' ');
                    }

                    try this.printType(param.type);
                    try this.w.writeByte(' ');
                    try this.w.writeAll(param.name.toString(this.src));

                    for (param.array_members) |arr_mem| {
                        try this.w.writeByte('[');
                        try this.printExpression(arr_mem, null);
                        try this.w.writeByte(']');
                    }
                }
                try this.w.writeByte(')');
                try this.printStatement(.{ .block = node.body });
            },

            .var_decl => |node| try this.printVarDecl(node),

            .precision => |node| {
                try this.w.writeAll("precision ");
                try this.w.writeAll(node.precision.toString());
                try this.w.writeByte(' ');
                try this.w.writeAll(node.name.toString(this.src));
                try this.w.writeByte(';');
            },
        }

        this.is_new_line = std.meta.activeTag(top_decl) == .directive;
    }

    fn printStatement(this: *Printer, stmnt: ast.Statement) Error!void {
        switch (stmnt) {
            .expression => |node| {
                try this.printExpression(node, null);
                try this.w.writeByte(';');
            },
            .directive => |node| {
                // Directives must be on their own line
                if (!this.is_new_line) try this.w.writeByte('\n');
                try this.w.writeAll(node.toString(this.src));
                try this.w.writeByte('\n');
            },
            .block => |node| {
                try this.w.writeByte('{');
                for (node.children) |child| {
                    try this.printStatement(child);
                }
                try this.w.writeByte('}');
            },
            .var_decl => |node| try this.printVarDecl(node),
            .@"if" => |node| {
                try this.w.writeAll("if(");
                try this.printExpression(node.condition.*, null);
                try this.w.writeByte(')');
                try this.printStatement(node.consequent.*);
                if (node.alternate) |alternate| {
                    try this.w.writeAll("else");
                    try this.printStatement(alternate.*);
                }
            },
        }
    }

    fn printExpression(this: *Printer, expr: ast.Expression, prev_prec: ?usize) Error!void {
        const this_prec = expr.getPrecedence();
        if (this_prec) |tp| if (prev_prec) |pp| {
            if (tp < pp) {
                try this.w.writeByte('(');
                try this.printExpression(expr, null);
                try this.w.writeByte(')');
                return;
            }
        };

        switch (expr) {
            .identifier => |*token| try this.w.writeAll(token.toString(this.src)),
            .number => |number| switch (number) {
                .src => |src| try this.w.writeAll(src.toString(this.src)),
                .custom => |num| try this.w.printFloat(num, .{}),
            },
            .call => |node| {
                try this.printExpression(node.subject.*, this_prec);
                try this.w.writeByte('(');

                for (node.args, 0..) |arg, i| {
                    if (i != 0) try this.w.writeByte(',');
                    try this.printExpression(arg, null);
                }

                try this.w.writeByte(')');
            },
            .wrapped => |node| {
                try this.w.writeByte('(');
                try this.printExpression(node.*, null);
                try this.w.writeByte(')');
            },
            .dot => |node| {
                try this.printExpression(node.subject.*, this_prec);
                try this.w.writeByte('.');
                try this.w.writeAll(node.field.toString(this.src));
            },
            .unary => |node| {
                try this.w.writeAll(node.op.toString());
                try this.printExpression(node.subject.*, this_prec);
            },
            .suffix => |node| {
                try this.printExpression(node.subject.*, this_prec);
                try this.w.writeAll(node.op.toString());
            },
            .binary, .assign => |node| {
                try this.printExpression(node.left.*, this_prec);
                try this.w.writeAll(node.op.toString());
                try this.printExpression(node.right.*, this_prec);
            },
            .index => |node| {
                try this.printExpression(node.subject.*, this_prec);
                try this.w.writeByte('[');
                try this.printExpression(node.index.*, null);
                try this.w.writeByte(']');
            },
        }
    }
};

fn isNextIdentifier(expr: *ast.Expression) bool {
    return switch (expr.*) {
        .identifier => true,
        .number => true,
        .call => |*node| isNextIdentifier(node.subject),
        .index => |*node| isNextIdentifier(node.subject),
        .dot => |*node| isNextIdentifier(node.subject),
        .binary, .assign => |*node| isNextIdentifier(node.left),
        .unary => |*node| switch (node.op) {
            .new, .yield, .await => true,
            else => false,
        },

        // There are a bunch of cases missing here,
        // but none of them are relevant for "correct" code
        else => false,
    };
}

pub fn print(nodes: []ast.TopDecl, w: *std.Io.Writer, src: []const u8) !void {
    var p = Printer{
        .w = w,
        .src = src,
    };

    for (nodes) |node| {
        try p.printTopDecl(node);
    }
}
