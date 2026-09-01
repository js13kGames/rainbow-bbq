const std = @import("std");
const path = std.Io.Dir.path;
const js_minify = @import("js_minify.zig");

pub const MinifyOptions = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    src_dir: std.Io.Dir,
};

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    const cwd = std.Io.Dir.cwd();

    const dname_in = args[1];
    const fname_in = if (args.len > 3) args[3] else "index.html";
    const src_dir = try cwd.openDir(init.io, dname_in, .{});
    const src = try src_dir.readFileAlloc(init.io, fname_in, init.gpa, .unlimited);
    defer init.gpa.free(src);

    const fname_out = args[2];
    var out_file = try cwd.createFile(init.io, fname_out, .{});
    var out_buf: [2048]u8 = undefined;
    var w = out_file.writer(init.io, &out_buf);

    try minify(src, &w.interface, &.{
        .gpa = init.gpa,
        .io = init.io,
        .src_dir = src_dir,
    });
    try w.flush();
}

/// Assumes whitespace is insignificant, but respects token separation
pub fn minify(src: []const u8, w: *std.Io.Writer, options: *const MinifyOptions) !void {
    var r = std.Io.Reader.fixed(src);

    var has_whitespace: bool = false;
    var prev_char: u8 = 0;

    while (r.seek != r.end) {
        const char = r.takeByte() catch break;
        if (std.ascii.isWhitespace(char)) {
            has_whitespace = true;
            continue;
        }

        // Ok... lets see here
        if (char == '<') tag: {
            const i = r.seek;

            r.seek -= 1;
            var tag = readTagOpen(&r, options) catch |err| switch (err) {
                else => return err,
                error.InvalidTag, error.EndOfStream => {
                    r.seek = i;
                    break :tag;
                },
            };
            defer tag.deinit(options.gpa);

            // Ok, what tag is this?
            if (std.ascii.eqlIgnoreCase("script", tag.name)) script: {
                const attr_idx = tag.findAttrWithValue("src") orelse break :script;

                // Make sure we don't have any content in this script tag
                try skipWhitespace(&r);
                if (try r.peekByte() != '<') {
                    break :script;
                }

                // Epic, now read attribute and print tag
                const attr = tag.attributes.swapRemove(attr_idx);
                try tag.print(w);

                // Print JS content
                try printJs(w, attr.value.?, options);
                prev_char = 0;
                has_whitespace = false;
                continue;
            }

            // Ok, since we HAVE the tag, lets minify it a liiiitle bit
            try tag.print(w);
            has_whitespace = false;
            prev_char = '>';
            continue;
        }

        // Minify strings by removing quotes, if possible
        if (char == '"') {}

        if (has_whitespace and
            std.ascii.isAlphanumeric(char) == std.ascii.isAlphanumeric(prev_char) and
            std.mem.findScalar(u8, ";<>{}", char) == null)
        {
            try w.writeByte(' ');
        }
        try w.writeByte(char);

        prev_char = char;
        has_whitespace = false;
    }
}

const TagOpen = struct {
    name: []const u8,
    attributes: std.ArrayList(Attribute),

    fn deinit(this: *TagOpen, gpa: std.mem.Allocator) void {
        this.attributes.deinit(gpa);
    }

    fn findAttr(this: *const TagOpen, name: []const u8) ?usize {
        for (this.attributes.items, 0..) |attr, i| {
            if (std.ascii.eqlIgnoreCase(name, attr.name)) {
                return i;
            }
        }

        return null;
    }

    fn findAttrWithValue(this: *const TagOpen, name: []const u8) ?usize {
        for (this.attributes.items, 0..) |attr, i| {
            if (std.ascii.eqlIgnoreCase(name, attr.name)) {
                return if (attr.value == null) null else i;
            }
        }

        return null;
    }

    fn print(this: *const TagOpen, w: *std.Io.Writer) !void {
        try w.writeByte('<');
        try w.writeAll(this.name);

        var need_whitespace = true;
        for (this.attributes.items) |attr| {
            if (need_whitespace) try w.writeByte(' ');
            try w.writeAll(attr.name);
            if (attr.value) |value| {
                try w.writeByte('=');
                const needs_escape = attr.valueNeedsEscape();
                if (needs_escape) try w.writeByte('"');
                try w.writeAll(value);
                if (needs_escape) try w.writeByte('"');
                need_whitespace = !needs_escape;
            } else {
                need_whitespace = true;
            }
        }

        try w.writeByte('>');
    }
};

const Attribute = struct {
    name: []const u8,
    value: ?[]const u8,

    fn valueNeedsEscape(this: *const Attribute) bool {
        const value = this.value orelse return false;

        for (value) |char| {
            if (std.mem.findScalar(u8, "<>\" \n\r\t", char) != null) {
                return true;
            }
        }

        return false;
    }
};

/// Only reads the opening tag.
/// Any tag contents and the end tag are not read.
/// Only tag name and attributes
fn readTagOpen(r: *std.Io.Reader, options: *const MinifyOptions) !TagOpen {
    r.seek += 1;
    try skipWhitespace(r);
    if (!std.ascii.isAlphanumeric(try r.peekByte())) {
        return error.InvalidTag;
    }

    const name_start = r.seek;
    const name = name: {
        while (true) {
            const char = try r.takeByte();
            if (!std.ascii.isAlphanumeric(char)) {
                r.seek -= 1;
                break :name r.buffer[name_start..r.seek];
            }
        }
    };

    // Ok, now read attributes
    var attrs = std.ArrayList(Attribute).empty;

    while (true) {
        try skipWhitespace(r);

        const char = try r.peekByte();
        if (char == '>') {
            r.seek += 1;
            break;
        }

        if (std.ascii.isAlphanumeric(char)) {
            try attrs.append(options.gpa, try readAttr(r));
            continue;
        }

        // Nope
        return error.InvalidTag;
    }

    return .{
        .name = name,
        .attributes = attrs,
    };
}

fn readAttr(r: *std.Io.Reader) !Attribute {
    const name_start = r.seek;
    const name = name: {
        while (true) {
            const char = try r.takeByte();
            if (!std.ascii.isAlphanumeric(char) and char != '_') {
                r.seek -= 1;
                break :name r.buffer[name_start..r.seek];
            }
        }
    };

    // Find equals sign
    try skipWhitespace(r);
    if (try r.peekByte() != '=') {
        r.seek -= 1;
        return .{
            .name = name,
            .value = null,
        };
    }

    // Find value
    r.seek += 1;
    try skipWhitespace(r);
    if (try r.peekByte() == '"') {
        r.seek += 1;
        const value_start = r.seek;

        while (true) {
            const char = try r.takeByte();
            if (char == '"') {
                return .{
                    .name = name,
                    .value = r.buffer[value_start .. r.seek - 1],
                };
            }
        }
    }

    // Otherwise, go until we find whitespace
    const value_start = r.seek;
    while (true) {
        const char = try r.takeByte();
        if (std.ascii.isWhitespace(char)) {
            r.seek -= 1;
            return .{
                .name = name,
                .value = r.buffer[value_start..r.seek],
            };
        }
    }
}

fn skipWhitespace(r: *std.Io.Reader) !void {
    while (r.seek != r.end) {
        const char = try r.takeByte();
        if (!std.ascii.isWhitespace(char)) {
            r.seek -= 1;
            break;
        }
    }
}

fn printJs(w: *std.Io.Writer, src_fname: []const u8, options: *const MinifyOptions) !void {
    const src_file = try options.src_dir.readFileAlloc(options.io, src_fname, options.gpa, .unlimited);
    defer options.gpa.free(src_file);

    try js_minify.minify(src_file, w, .{
        .gpa = options.gpa,
        .io = options.io,
        .src = src_file,
        .src_dir = options.src_dir,
        .src_path = src_fname,
    });
}
