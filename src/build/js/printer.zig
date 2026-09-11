const std = @import("std");

const ast = @import("ast.zig");
const Token = @import("tokenizer.zig").Token;

const Error = std.Io.Writer.Error;

const Printer = struct {
    w: *std.Io.Writer,
    src: []const u8,

    fn printStatement(this: *Printer, stmnt: ast.Statement, is_last: bool) Error!void {
        switch (stmnt) {
            .expression => |node| {
                try this.printExpression(node, null);
                if (!is_last) try this.w.writeByte(';');
            },
            .block => |node| {
                try this.w.writeByte('{');
                for (node.children, 0..) |child, i| {
                    try this.printStatement(child, i == node.children.len - 1);
                }
                try this.w.writeByte('}');
            },
            .@"var" => |node| {
                try this.w.writeAll(@tagName(node.decl_type));
                try this.w.writeByte(' ');
                try this.w.writeAll(node.name.toString(this.src));

                if (node.value) |value| {
                    try this.w.writeByte('=');
                    try this.printExpression(value.*, null);
                }

                if (!is_last) try this.w.writeByte(';');
            },
            .@"if" => |node| {
                try this.w.writeAll("if(");
                try this.printExpression(node.condition.*, null);
                try this.w.writeByte(')');
                try this.printStatement(node.consequent.*, is_last and node.alternate == null);
                if (node.alternate) |alternate| {
                    try this.w.writeAll("else");
                    try this.printStatement(alternate.*, is_last);
                }
            },
            .throw => |node| {
                try this.w.writeAll("throw");
                if (isNextIdentifier(node.subject)) try this.w.writeByte(' ');
                try this.printExpression(node.subject.*, null);
                if (!is_last) try this.w.writeByte(';');
            },
            .@"try" => |node| {
                try this.w.writeAll("try");
                try this.printStatement(.{ .block = node.@"try" }, false);
                if (node.@"catch") |catch_block| {
                    try this.w.writeAll("catch");
                    if (catch_block.capture) |capture| {
                        try this.w.print("({s})", .{capture.toString(this.src)});
                    }
                    try this.printStatement(.{ .block = catch_block.block }, false);
                }
                if (node.finally) |finally| {
                    try this.w.writeAll("finally");
                    try this.printStatement(.{ .block = finally }, false);
                }
            },
            .@"return" => |node| {
                try this.w.writeAll("return");
                if (node) |expr| {
                    if (isNextIdentifier(&expr)) try this.w.writeByte(' ');
                    try this.printExpression(expr, null);
                }
                if (!is_last) try this.w.writeByte(';');
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
            .identifier, .string => |*token| try this.w.writeAll(token.toString(this.src)),
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
            .arrow_fn => |node| {
                if (node.async) try this.w.writeAll("async");
                if (node.params.len == 1 and node.params[0].default_value == null) {
                    const token = node.params[0].name;
                    try this.w.writeAll(token.toString(this.src));
                } else {
                    try this.w.writeByte('(');
                    for (node.params, 0..) |param, i| {
                        if (i != 0) try this.w.writeByte(',');
                        try this.w.writeAll(param.name.toString(this.src));
                        if (param.default_value) |default_value| {
                            try this.w.writeByte('=');
                            try this.printExpression(default_value.*, null);
                        }
                    }
                    try this.w.writeAll(")");
                }

                try this.w.writeAll("=>");
                switch (node.body) {
                    .block => |body| try this.printStatement(.{ .block = body.* }, false),
                    .expression => |body| try this.printExpression(body.*, this_prec),
                }
            },
            .dot => |node| {
                try this.printExpression(node.subject.*, this_prec);
                try this.w.writeAll(node.dot_type.toString());
                try this.w.writeAll(node.field.toString(this.src));
            },
            .unary => |node| {
                switch (node.op) {
                    .await, .yield, .new => {
                        try this.w.writeAll(node.op.toString());
                        if (isNextIdentifier(node.subject)) try this.w.writeByte(' ');
                    },
                    else => try this.w.writeAll(node.op.toString()),
                }

                try this.printExpression(node.subject.*, this_prec);
            },
            .suffix => |node| {
                try this.printExpression(node.subject.*, this_prec);
                try this.w.writeAll(node.op.toString());
            },
            .object => |node| {
                try this.w.writeByte('{');
                for (node.entries, 0..) |elem, i| {
                    if (i != 0) try this.w.writeByte(',');
                    switch (elem.key) {
                        .identifier, .number, .string => |token| try this.w.writeAll(token.toString(this.src)),
                        .expression => |key| {
                            try this.w.writeByte('[');
                            try this.printExpression(key.*, null);
                            try this.w.writeByte(']');
                        },
                    }
                    try this.w.writeByte(':');
                    try this.printExpression(elem.value.*, null);
                }
                try this.w.writeByte('}');
            },
            .binary, .assign => |node| {
                try this.printExpression(node.left.*, this_prec);
                try this.w.writeAll(node.op.toString());
                try this.printExpression(node.right.*, this_prec);
            },
            .array => |node| {
                try this.w.writeByte('[');
                for (node.values, 0..) |value, i| {
                    if (i != 0) try this.w.writeByte(',');
                    try this.printExpression(value, null);
                }
                try this.w.writeByte(']');
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

fn isNextIdentifier(expr: *const ast.Expression) bool {
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

pub fn print(nodes: []ast.Statement, w: *std.Io.Writer, src: []const u8) !void {
    var p = Printer{
        .w = w,
        .src = src,
    };

    for (nodes, 0..) |node, i| {
        try p.printStatement(node, i == nodes.len - 1);
    }
}
