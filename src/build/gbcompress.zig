//! Based on https://github.com/gitendo/gbcp/tree/master/gbcomp/

const std = @import("std");

const Command = enum(u2) {
    repeat_u8 = 0,
    repeat_u16 = 1,
    repeat_string = 2,
    trash = 3,

    fn minLength(comptime this: Command) usize {
        return switch (this) {
            .repeat_u8 => 3,
            .repeat_u16 => 3,
            .repeat_string => 4,
            .trash => 1,
        };
    }

    fn lengthOffset(comptime this: Command) usize {
        return switch (this) {
            .repeat_u8 => this.minLength() - 1,
            else => this.minLength(),
        };
    }

    fn maxLength(comptime this: Command) usize {
        return 63 + this.lengthOffset();
    }
};

const Packet = packed struct(u8) {
    length: u6,
    command: Command,

    fn init(comptime command: Command, length: usize) Packet {
        std.debug.assert(length >= command.minLength());
        std.debug.assert(length <= command.maxLength());

        return .{
            .command = command,
            .length = @truncate(length - command.lengthOffset()),
        };
    }

    inline fn isEnd(this: Packet) bool {
        return this.command == .repeat_u8 and this.length == 0;
    }
};

pub fn compress(in: []const u8, out: *std.Io.Writer) !void {
    const Compressor = struct {
        const Compressor = @This();

        in: []const u8,
        pos: usize,
        out: *std.Io.Writer,
        trash_num: usize,

        fn getU8(this: *const Compressor, offset: usize) u8 {
            return if (offset >= this.in.len) 0 else this.in[offset];
        }

        fn getU16(this: *const Compressor, offset: usize) u16 {
            return if (offset + 1 >= this.in.len) 0 else std.mem.readInt(u16, this.in[offset .. offset + 2][0..2], .little);
        }

        inline fn eof(this: Compressor) bool {
            return this.pos >= this.in.len;
        }

        fn writeU8(this: *Compressor, repeats: usize, val: u8) !void {
            try this.flushTrash();
            const packet = Packet.init(.repeat_u8, repeats);
            try this.out.writeByte(@bitCast(packet));
            try this.out.writeByte(val);
        }

        fn writeU16(this: *Compressor, repeats: usize, val: u16) !void {
            try this.flushTrash();
            const packet = Packet.init(.repeat_u16, repeats);
            try this.out.writeByte(@bitCast(packet));
            try this.out.writeInt(u16, @truncate(val), .little);
        }

        fn writeStr(this: *Compressor, repeats: usize, start: usize) !void {
            std.debug.assert(start < 0x10000);
            try this.flushTrash();
            const packet = Packet.init(.repeat_string, repeats);
            try this.out.writeByte(@bitCast(packet));
            try this.out.writeInt(u16, @truncate(start), .little);
        }

        fn flushTrash(this: *Compressor) !void {
            if (this.trash_num != 0) {
                const packet = Packet.init(.trash, this.trash_num);
                try this.out.writeByte(@bitCast(packet));
                try this.out.writeAll(this.in[this.pos - this.trash_num .. this.pos]);
                this.trash_num = 0;
            }
        }
    };

    var c = Compressor{
        .in = in,
        .pos = 0,
        .out = out,
        .trash_num = 0,
    };

    while (!c.eof()) {

        // Find number of repeated u8
        const u8_val = c.getU8(c.pos);
        var u8_num: usize = 0;
        while (u8_num < Command.repeat_u8.maxLength() and
            c.pos + u8_num < in.len and
            c.getU8(c.pos + u8_num) == u8_val) u8_num += 1;

        // Find number of repeated u16
        const u16_val = c.getU16(c.pos);
        var u16_num: usize = 0;
        while (u16_num < Command.repeat_u16.maxLength() and
            c.pos + u16_num * 2 + 1 < in.len and
            c.getU16(c.pos + u16_num * 2) == u16_val) u16_num += 1;

        // Find best repeated string
        var str_start: usize = 0;
        var str_num: usize = 0;
        for (0..c.pos) |str_start_current| {
            var str_num_current: usize = 0;

            while (str_num_current < Command.repeat_string.maxLength() and
                c.pos + str_num_current + 1 < c.pos and
                c.getU8(str_start_current + str_num_current) == c.getU8(c.pos + str_num_current))
            {
                str_num_current += 1;
            }

            if (str_num_current > str_num) {
                str_start = str_start_current;
                str_num = str_num_current;
            }
        }

        // Determine which packet to emit
        if (u8_num >= Command.repeat_u8.minLength() and u8_num > u16_num and u8_num > str_num) {
            try c.writeU8(u8_num, u8_val);
            c.pos += u8_num;
            continue;
        }

        if (u16_num >= Command.repeat_u16.minLength() and u16_num * 2 > str_num) {
            try c.writeU16(u16_num, u16_val);
            c.pos += u16_num * 2;
            continue;
        }

        if (str_num >= Command.repeat_string.minLength()) {
            try c.writeStr(str_num, str_start);
            c.pos += str_num;
            continue;
        }

        // No packet, emit trash
        if (c.trash_num >= Command.trash.maxLength()) {
            try c.flushTrash();
        }
        c.trash_num += 1;
        c.pos += 1;
    }

    try c.flushTrash();
    try out.writeByte(0);
}

/// Output buffer is expected to have enough space
pub fn decompress(in: []const u8, out: []u8) !void {
    const Decompressor = struct {
        const Decompressor = @This();

        in: []const u8,
        in_pos: usize,
        out: []u8,
        out_pos: usize,

        inline fn getU8(this: *Decompressor) u8 {
            defer this.in_pos += 1;
            return this.in[this.in_pos];
        }

        inline fn getU16(this: *Decompressor) u16 {
            defer this.in_pos += 2;
            return std.mem.readInt(u16, this.in[this.in_pos .. this.in_pos + 2][0..2], .little);
        }

        inline fn eof(this: Decompressor) bool {
            return this.in_pos >= this.in.len;
        }
    };

    var d = Decompressor{
        .in = in,
        .in_pos = 0,
        .out = out,
        .out_pos = 0,
    };

    while (!d.eof()) {
        const packet: Packet = @bitCast(d.getU8());
        if (packet.isEnd()) return;

        switch (packet.command) {
            .repeat_u8 => {
                const val = d.getU8();
                const repeats: usize = Command.repeat_u8.lengthOffset() + packet.length;
                @memset(out[d.out_pos .. d.out_pos + repeats], val);
                d.out_pos += repeats;
            },

            .repeat_u16 => {
                const val = d.getU16();
                const repeats: usize = Command.repeat_u16.lengthOffset() + packet.length;

                for (0..repeats) |_| {
                    std.mem.writeInt(u16, out[d.out_pos .. d.out_pos + 2][0..2], val, .little);
                    d.out_pos += 2;
                }
            },

            .repeat_string => {
                const start: usize = d.getU16();
                const length: usize = Command.repeat_string.lengthOffset() + packet.length;
                if (d.out_pos + length > out.len) @panic("bad length");
                if (start + length > d.out.len) @panic("bad end thing");
                if (start + length > d.out_pos) std.debug.panic("overlap @ {}", .{d.in_pos - 3});

                @memcpy(
                    d.out[d.out_pos .. d.out_pos + length],
                    d.out[start .. start + length],
                );
                d.out_pos += length;
            },

            .trash => {
                const length: usize = Command.trash.lengthOffset() + packet.length;
                @memcpy(
                    d.out[d.out_pos .. d.out_pos + length],
                    d.in[d.in_pos .. d.in_pos + length],
                );
                d.in_pos += length;
                d.out_pos += length;
            },
        }
    }
}

test "compress u8" {
    var w = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w.deinit();
    const in = [_]u8{ 7, 7, 7, 7, 7, 7, 7, 7, 7 };
    try compress(&in, &w.writer);

    try std.testing.expect(std.mem.eql(u8, w.written(), &.{
        @bitCast(Packet.init(.repeat_u8, 9)),
        7,
        0,
    }));
}

test "does it work" {
    var xoro = std.Random.Xoroshiro128.init(78732894);
    const rng = xoro.random();
    var bytes: [1024]u8 = undefined;
    rng.bytes(&bytes);

    var w = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w.deinit();
    try compress(&bytes, &w.writer);

    var out: [1024]u8 = undefined;
    try decompress(w.written(), &out);

    try std.testing.expect(std.mem.eql(u8, &bytes, &out));
}

test "w har" {
    const bytes = "123456789123456789123456789123456789123456789123456789123456789";

    var w = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer w.deinit();
    try compress(bytes, &w.writer);

    var out: [bytes.len]u8 = undefined;
    try decompress(w.written(), &out);

    try std.testing.expect(std.mem.eql(u8, bytes, &out));
}
