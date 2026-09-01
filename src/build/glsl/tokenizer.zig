const std = @import("std");

const MinifyArgs = @import("../glsl_minify.zig").MinifyArgs;

pub const Token = struct {
    kind: Kind,
    start: u32,
    end: u32,

    pub const Kind = enum {
        paren_open,
        paren_close,
        square_open,
        square_close,
        curly_open,
        curly_close,
        angle_open,
        angle_close,

        plus,
        minus,
        asterisk,
        slash,
        mod,
        or_bin,
        or_bool,
        and_bin,
        and_bool,
        xor_bin,

        plus_eq,
        minus_eq,
        asterisk_eq,
        slash_eq,
        mod_eq,
        or_eq,
        and_eq,
        xor_eq,

        equals,
        compare,
        compare_not,
        less_or_equal,
        greater_or_equal,

        shift_left,
        shift_right,

        not,
        neg,
        increment,
        decrement,

        question,
        colon,
        semicolon,
        comma,
        dot,

        number,
        identifier,
        directive,

        @"const",
        precision,
        uniform,
        in,
        out,
        inout,
        lowp,
        mediump,
        highp,
        layout,
        location,
        flat,
        smooth,

        @"return",
        @"while",
        @"for",
        @"if",
        @"else",
        @"break",
        @"continue",

        pub fn toString(this: Kind) []const u8 {
            for (symbol_combos.values(), 0..) |key, i| {
                if (key == this) {
                    return symbol_combos.keys()[i];
                }
            }
            for (keywords.values(), 0..) |key, i| {
                if (key == this) {
                    return keywords.keys()[i];
                }
            }
            std.debug.panic("could not get string representation of token: {}", .{this});
        }
    };

    /// The returned string is either from the src array, or a const string.
    /// No need to free it.
    pub fn toString(this: Token, src: []const u8) []const u8 {
        return switch (this.kind) {
            .number, .identifier, .directive => src[this.start..this.end],
            else => this.kind.toString(),
        };
    }
};

pub const symbol_combos = std.StaticStringMap(Token.Kind).initComptime(.{
    .{ "(", .paren_open },
    .{ ")", .paren_close },
    .{ "[", .square_open },
    .{ "]", .square_close },
    .{ "{", .curly_open },
    .{ "}", .curly_close },
    .{ "<", .angle_open },
    .{ ">", .angle_close },

    .{ "+", .plus },
    .{ "-", .minus },
    .{ "*", .asterisk },
    .{ "/", .slash },
    .{ "%", .mod },
    .{ "|", .or_bin },
    .{ "||", .or_bool },
    .{ "&", .and_bin },
    .{ "&&", .and_bool },
    .{ "^", .xor_bin },

    .{ "+=", .plus_eq },
    .{ "-=", .minus_eq },
    .{ "*=", .asterisk_eq },
    .{ "/=", .slash_eq },
    .{ "%=", .mod_eq },
    .{ "|=", .or_eq },
    .{ "&=", .and_eq },
    .{ "^=", .xor_eq },

    .{ "=", .equals },
    .{ "==", .compare },
    .{ "!=", .compare_not },
    .{ "<=", .less_or_equal },
    .{ ">=", .greater_or_equal },

    .{ "<<", .shift_left },
    .{ ">>", .shift_right },

    .{ "!", .not },
    .{ "~", .neg },
    .{ "++", .increment },
    .{ "--", .decrement },

    .{ "?", .question },
    .{ ":", .colon },
    .{ ";", .semicolon },
    .{ ",", .comma },
    .{ ".", .dot },
});

pub const keywords = std.StaticStringMap(Token.Kind).initComptime(.{
    .{ "precision", .precision },
    .{ "const", .@"const" },
    .{ "uniform", .uniform },
    .{ "in", .in },
    .{ "out", .out },
    .{ "inout", .inout },
    .{ "lowp", .lowp },
    .{ "mediump", .mediump },
    .{ "highp", .highp },
    .{ "layout", .layout },
    .{ "location", .location },
    .{ "flat", .flat },
    .{ "smooth", .smooth },

    .{ "return", .@"return" },
    .{ "while", .@"while" },
    .{ "for", .@"for" },
    .{ "if", .@"if" },
    .{ "else", .@"else" },
    .{ "break", .@"break" },
    .{ "continue", .@"continue" },
});

const Tokenizer = struct {
    r: std.Io.Reader,

    fn eof(this: *Tokenizer) bool {
        return this.r.seek >= this.r.end;
    }

    fn peekByte(this: *Tokenizer) u8 {
        return this.r.peekByte() catch 0;
    }

    fn peekBytes(this: *Tokenizer, comptime n: usize) [n]u8 {
        const s = this.r.seek;
        var out: [2]u8 = undefined;
        inline for (0..n) |i| {
            out[i] = this.nextByte();
        }
        this.r.seek = s;
        return out;
    }

    fn nextByte(this: *Tokenizer) u8 {
        return this.r.takeByte() catch 0;
    }

    fn nextToken(this: *Tokenizer) ?Token {
        this.skipWhitespace();

        const token_start = this.r.seek;
        const char = this.peekByte();
        if (char == 0) return null;

        // Read pre-compiler directive
        if (char == '#') {
            this.readDirective();
            return .{
                .kind = .directive,
                .start = @truncate(token_start),
                .end = @truncate(this.r.seek),
            };
        }

        // Read identifier
        if (std.ascii.isAlphabetic(char) or char == '_') {
            const ident = this.readIdentifier();
            return .{
                .kind = keywords.get(ident) orelse .identifier,
                .start = @truncate(token_start),
                .end = @truncate(this.r.seek),
            };
        }

        // Read number
        if (std.ascii.isDigit(char)) {
            this.readNumber();
            return .{
                .kind = .number,
                .start = @truncate(token_start),
                .end = @truncate(this.r.seek),
            };
        }

        // Read as special character sequence
        const seq = this.readSequence();
        return .{
            .kind = seq,
            .start = @truncate(token_start),
            .end = @truncate(this.r.seek),
        };
    }

    fn readDirective(this: *Tokenizer) void {
        while (true) {
            const char = this.peekByte();
            if (char == '\n' or char == '\r' or char == 0) {
                return;
            }

            this.r.seek += 1;
        }
    }

    fn readIdentifier(this: *Tokenizer) []const u8 {
        const start = this.r.seek;

        while (true) {
            const char = this.peekByte();
            if (!std.ascii.isAlphanumeric(char) and char != '_') {
                return this.r.buffer[start..this.r.seek];
            }

            this.r.seek += 1;
        }
    }

    fn readNumber(this: *Tokenizer) void {
        const chars_lower = "0123456789ABCDEF";
        const chars_upper = "0123456789abcdef";

        var allow_decimal = true;
        var decimal = false;
        var base: usize = 10;

        // If first digit is 0, the following character must be:
        // 'x': switch to base 16
        // 'b': switch to base 2
        // '.': base 10 decimal number
        // '1-7': switch to base 8
        // 'u': unsigned number 0
        const first = this.peekByte();
        if (first == '0') {
            this.r.seek += 1;
            switch (this.peekByte()) {
                'x' => {
                    base = 16;
                    allow_decimal = false;
                    this.r.seek += 1;
                },
                'b' => {
                    base = 2;
                    allow_decimal = false;
                    this.r.seek += 1;
                },
                '1'...'7' => {
                    base = 8;
                    allow_decimal = false;
                    this.r.seek += 1;
                },
                '.' => {
                    base = 10;
                    decimal = true;
                    this.r.seek += 1;
                },
                'u' => {
                    this.r.seek += 1;
                    return;
                },

                // Must've been the wind
                else => return,
            }
        }

        while (true) {
            const char = this.peekByte();
            switch (char) {
                '.' => {
                    if (!allow_decimal) {
                        std.debug.panic("invalid number literal, decimal not allowed", .{});
                    }
                    if (decimal) {
                        std.debug.panic("invalid number literal, decimal already specified", .{});
                    }
                    decimal = true;
                    this.r.seek += 1;
                    continue;
                },

                'u' => {
                    if (decimal) {
                        std.debug.panic("invalid number literal, unsigned suffix not allowed for fractional values", .{});
                    }
                    this.r.seek += 1;
                    return;
                },

                else => {},
            }

            _ = std.mem.findScalar(u8, chars_lower[0..base], char) orelse std.mem.findScalar(u8, chars_upper[0..base], char) orelse return;
            this.r.seek += 1;
        }
    }

    fn readSequence(this: *Tokenizer) Token.Kind {
        var str_buf: [8]u8 = undefined;
        var i: usize = 0;

        while (true) {
            str_buf[i] = this.peekByte();
            const str: []const u8 = str_buf[0 .. i + 1];

            if (!symbol_combos.has(str)) {
                return symbol_combos.get(str_buf[0..i]).?;
            }

            i += 1;
            this.r.seek += 1;
        }
    }

    fn skipWhitespace(this: *Tokenizer) void {
        while (true) {
            const bytes = this.peekBytes(2);
            if (std.ascii.isWhitespace(bytes[0])) {
                this.r.seek += 1;
                continue;
            }

            // Single-line comment
            if (bytes[0] == '/' and bytes[1] == '/') {
                this.r.seek += 2;
                while (true) {
                    const next = this.nextByte();
                    if (next == '\n' or next == 0) {
                        break;
                    }
                }

                continue;
            }

            // Multi-line comment
            if (bytes[0] == '/' and bytes[1] == '*') {
                this.r.seek += 2;

                while (true) {
                    const next = this.peekBytes(2);
                    if (next[0] == 0 or (next[0] == '*' and next[1] == '/')) {
                        this.r.seek += 2;
                        break;
                    }

                    this.r.seek += 1;
                }

                continue;
            }

            break;
        }
    }
};

/// Allocator is only used for an ArrayList.
/// Exceeding capacity is NOT cleaned up.
pub fn tokenize(arena: std.mem.Allocator, options: *const MinifyArgs) ![]Token {
    var t = Tokenizer{ .r = .fixed(options.src) };

    var tokens = std.ArrayList(Token).empty;
    defer tokens.deinit(arena);

    while (t.nextToken()) |token| {
        try tokens.append(arena, token);
    }

    return tokens.toOwnedSlice(arena);
}
