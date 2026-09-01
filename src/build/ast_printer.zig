const std = @import("std");

pub fn For(comptime Ast: type) type {
    return struct {
        const Token: type = Ast.Token;

        pub fn print(t: anytype, w: *std.Io.Writer, src: []const u8) std.Io.Writer.Error!void {
            var p = Printer{
                .w = w,
                .src = src,
            };

            try p.strNode(t);
        }

        pub fn dumpAndDie(t: anytype, src: []const u8, io: std.Io) noreturn {
            var stdout = std.Io.File.stderr();
            var buf: [2048]u8 = undefined;
            var fw = stdout.writer(io, &buf);

            print(t, &fw.interface, src) catch @panic("failed to print AST!");
            fw.flush() catch @panic("could not flush stdout!");
            @panic("die here");
        }

        const Printer = struct {
            w: *std.Io.Writer,
            i: usize = 0,
            src: []const u8,

            fn indent(this: *Printer) std.Io.Writer.Error!void {
                for (0..this.i) |_| {
                    try this.w.writeAll("  ");
                }
            }

            fn strNode(this: *Printer, node: anytype) std.Io.Writer.Error!void {
                const T = @TypeOf(node);

                switch (T) {
                    else => {},
                    Token => {
                        try this.w.print("{} ({s})", .{ node.kind, this.src[node.start..node.end] });
                        return;
                    },
                }

                switch (@typeInfo(T)) {
                    .@"union" => |t| {
                        const active = std.meta.activeTag(node);
                        inline for (t.fields) |field| {
                            const field_enum = @field(std.meta.Tag(T), field.name);
                            if (active == field_enum) {
                                const field_val = @field(node, field.name);
                                try this.strNode(field_val);
                                break;
                            }
                        }
                    },
                    .@"struct" => |t| {
                        if (t.fields.len == 0) {
                            try this.w.print("{s} {{}}");
                        } else {
                            try this.w.print("{s} {{\n", .{@typeName(T)});
                            this.i += 1;

                            inline for (t.fields) |field| {
                                try this.indent();
                                try this.w.print("{s}: ", .{field.name});
                                try this.strNode(@field(node, field.name));
                                try this.w.writeByte('\n');
                            }

                            this.i -= 1;
                            try this.indent();
                            try this.w.writeByte('}');
                        }
                    },
                    .pointer => |t| {
                        switch (t.size) {
                            .slice => {
                                if (node.len == 0) {
                                    try this.w.writeAll("[]");
                                } else {
                                    try this.w.writeAll("[\n");
                                    this.i += 1;
                                    for (node) |child| {
                                        try this.indent();
                                        try this.strNode(child);
                                        try this.w.writeByte('\n');
                                    }
                                    this.i -= 1;
                                    try this.indent();
                                    try this.w.writeByte(']');
                                }
                            },
                            .one => {
                                try this.strNode(node.*);
                            },
                            else => @compileError("no, bad"),
                        }
                    },
                    .@"enum" => {
                        try this.w.print("{}", .{node});
                    },
                    .bool => {
                        try this.w.writeAll(if (node) "true" else "false");
                    },
                    .optional => {
                        if (node) |val| {
                            try this.strNode(val);
                        } else {
                            try this.w.writeAll("null");
                        }
                    },
                    else => try this.w.print("UNKNOWN {s}", .{@typeName(T)}),
                }
            }
        };
    };
}
