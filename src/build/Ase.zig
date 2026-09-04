//! Partial and incomplete .ase file renderer
//! https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md

const Ase = @This();

const std = @import("std");

header: Header,
palette: [][4]u8,
frames: []const Frame,
layers: []const Layer,

pub fn deinit(this: *const Ase, gpa: std.mem.Allocator) void {
    gpa.free(this.palette);

    for (this.frames) |*frame| frame.deinit(gpa);
    gpa.free(this.frames);

    for (this.layers) |*layer| layer.deinit(gpa);
    gpa.free(this.layers);
}

pub fn pixelsPerFrame(this: *const Ase) usize {
    const cw = @as(usize, this.header.width);
    const ch = @as(usize, this.header.height);
    return cw * ch;
}

pub fn renderFrame(this: *const Ase, frame_idx: usize, buffer: [][4]u8) void {
    std.debug.assert(frame_idx < this.frames.len);
    std.debug.assert(buffer.len >= this.pixelsPerFrame());
    const frame = &this.frames[frame_idx];

    const cw = @as(usize, this.header.width);
    const ch = @as(usize, this.header.height);
    std.debug.assert(buffer.len == cw * ch);

    @memset(buffer, .{ 0, 0, 0, 0 });

    for (frame.cels) |cel| {
        std.debug.assert(cel.header.x >= 0);
        std.debug.assert(cel.header.y >= 0);
        const cel_x = @as(usize, @intCast(cel.header.x));
        const cel_y = @as(usize, @intCast(cel.header.y));
        const cel_w, const cel_h = switch (cel.extra_header) {
            .raw => |eh| .{ @as(usize, eh.width), @as(usize, eh.height) },
            .compressed_img => |eh| .{ @as(usize, eh.width), @as(usize, eh.height) },
            else => @panic("bad"),
        };
        std.debug.assert(cel_x + cel_w <= cw);
        std.debug.assert(cel_y + cel_h <= ch);

        var i: usize = 0;

        for (0..cel_h) |y| {
            for (0..cel_w) |x| {
                const src_pixel = switch (this.header.color_depth) {
                    .paletted => blk: {
                        const pix = cel.pixel_data[i];
                        i += 1;
                        break :blk this.palette[pix];
                    },

                    .rgba => blk: {
                        const color = cel.pixel_data[i .. i + 4][0..4].*;
                        i += 4;
                        break :blk color;
                    },

                    else => @panic("unimplemented"),
                };
                if (src_pixel[3] == 0) continue;

                buffer[(cel_y + y) * cw + (cel_x + x)] = src_pixel;
            }
        }
    }
}

pub const Header = packed struct {
    file_size: u32,
    magic: u16,
    frames: u16,
    width: u16,
    height: u16,
    color_depth: enum(u16) {
        paletted = 8,
        grayscale = 16,
        rgba = 32,

        pub fn bytesPerPixel(this: @This()) usize {
            return @intFromEnum(this) / 8;
        }
    },
    flags: packed struct(u32) {
        layer_opacity_valid: bool,
        layer_blend_groups: bool,
        layer_has_uuid: bool,
        _: u29,
    },
    speed: u16,
    unused_1: u32,
    unused_2: u32,
    transparent_color: u32,
    num_colors: u16,
    pixel_width: u8,
    pixel_height: u8,
    grid_x: i16,
    grid_y: i16,
    grid_width: u16,
    grid_height: u16,
    future: @Int(.unsigned, 8 * 84),

    comptime {
        std.debug.assert(@sizeOf(@This()) == 128);
    }
};

pub const Frame = struct {
    header: Frame.Header,
    cels: []const Cel,

    pub fn deinit(this: *const Frame, gpa: std.mem.Allocator) void {
        for (this.cels) |*cel| cel.deinit(gpa);
        gpa.free(this.cels);
    }

    pub const Header = packed struct {
        num_bytes: u32,
        magic: u16,
        old_chunks: u16,
        frame_duration: u16,
        unused: u16,
        new_chunks: u32,
    };
};

pub const Chunk = struct {
    pub const Kind = enum(u16) {
        palette = 0x0004,
        layer = 0x2004,
        cel = 0x2005,
        color_profile = 0x2007,
    };

    pub const Header = packed struct {
        num_bytes: u32,
        kind: Kind,
    };
};

pub const Layer = struct {
    header: Layer.Header,
    name: []const u8,

    pub fn deinit(this: *const Layer, gpa: std.mem.Allocator) void {
        gpa.free(this.name);
    }

    pub const Header = packed struct {
        flags: packed struct(u16) {
            visible: bool,
            editable: bool,
            lock_movement: bool,
            background: bool,
            prefer_linked_cells: bool,
            collapsed_group: bool,
            reference_layer: bool,
            _: u9 = 0,
        },

        kind: enum(u16) {
            normal = 0,
            group = 1,
            tilemap = 2,
        },

        child_level: u16,
        width: u16,
        height: u16,
        blend_mode: enum(u16) {
            normal = 0,
            multiply = 1,
            screen = 2,
            overlay = 3,
            darken = 4,
            lighten = 5,
            color_dodge = 6,
            color_burn = 7,
            hard_light = 8,
            soft_light = 9,
            difference = 10,
            exclusion = 11,
            hue = 12,
            saturation = 13,
            color = 14,
            luminosity = 15,
            addition = 16,
            subtract = 17,
            divide = 18,
        },

        opacity: u8,
        future: u24,
    };
};

pub const Cel = struct {
    header: Cel.Header,
    extra_header: Cel.ExtraHeader,
    pixel_data: []const u8,

    pub fn deinit(this: *const Cel, gpa: std.mem.Allocator) void {
        gpa.free(this.pixel_data);
    }

    pub const Kind = enum(u16) {
        raw = 0,
        linked = 1,
        compressed_img = 2,
        compressed_tilemap = 3,
    };

    pub const Header = packed struct {
        layer: u16,
        x: i16,
        y: i16,
        opacity: u8,
        kind: Kind,

        z: i16,
        future: u40,
    };

    pub const ExtraHeader = union(Kind) {
        pub const Raw = packed struct {
            width: u16,
            height: u16,
        };

        pub const Linked = packed struct {
            frame_position: u16,
        };

        pub const CompressedImg = packed struct {
            width: u16,
            height: u16,
        };

        pub const CompressedTilemap = packed struct {
            width: u16,
            height: u16,
            bits_per_tile: u16,
            bitmask_inded: u32,
            bitmask_xflip: u32,
            bitmask_yflip: u32,
            bitmask_dflip: u32,
            reserved: u80,
        };

        raw: Raw,
        linked: Linked,
        compressed_img: CompressedImg,
        compressed_tilemap: CompressedTilemap,
    };
};

pub fn parse(src: []const u8, gpa: std.mem.Allocator) !Ase {
    var r = std.Io.Reader.fixed(src);
    const ase_header = try r.takeStruct(Ase.Header, .little);

    std.debug.assert(ase_header.magic == 0xA5E0);
    std.debug.assert(ase_header.pixel_width == 1);
    std.debug.assert(ase_header.pixel_height == 1);

    var frames = try std.ArrayList(Ase.Frame).initCapacity(gpa, ase_header.frames);
    errdefer {
        for (frames.items) |*frame| frame.deinit(gpa);
        frames.deinit(gpa);
    }

    var layers = std.ArrayList(Ase.Layer).empty;
    errdefer {
        for (layers.items) |*layer| layer.deinit(gpa);
        layers.deinit(gpa);
    }

    var palette: ?[][4]u8 = undefined;
    errdefer if (palette) |pal| gpa.free(pal);

    for (0..ase_header.frames) |_| {
        const frame_start = r.seek;
        const frame_header = try r.takeStruct(Ase.Frame.Header, .little);
        defer std.debug.assert(r.seek == frame_start + frame_header.num_bytes);

        std.debug.assert(frame_header.magic == 0xF1FA);
        std.debug.assert(frame_header.new_chunks != 0);

        var cels = std.ArrayList(Ase.Cel).empty;
        errdefer {
            for (cels.items) |*cel| cel.deinit(gpa);
            cels.deinit(gpa);
        }

        for (0..frame_header.new_chunks) |_| {
            const chunk_start = r.seek;
            const chunk_header = try r.takeStruct(Ase.Chunk.Header, .little);
            defer std.debug.assert(r.seek == chunk_start + chunk_header.num_bytes);

            switch (chunk_header.kind) {
                // Don't care
                .color_profile => _ = try r.take(chunk_header.num_bytes - 6),

                .palette => {
                    const colors = try gpa.alloc([4]u8, 256);
                    errdefer gpa.free(colors);
                    @memset(colors, .{ 0, 0, 0, 0 });

                    const num_packets = try r.takeInt(u16, .little);
                    var color_index: usize = 0;
                    for (0..num_packets) |_| {
                        const skip = try r.takeByte();
                        const num_colors = try r.takeByte();
                        color_index += skip;

                        for (0..num_colors) |_| {
                            const color = try r.takeArray(3);
                            colors[color_index] = .{
                                color[0],
                                color[1],
                                color[2],
                                if (ase_header.transparent_color == color_index) 0 else 255,
                            };
                            color_index += 1;
                        }
                    }

                    palette = colors;
                },

                .layer => {
                    const layer_header = try r.takeStruct(Ase.Layer.Header, .little);
                    const name_len = try r.takeInt(u16, .little);
                    const name = try r.readAlloc(gpa, name_len);
                    errdefer gpa.free(name);

                    const tileset_index = if (layer_header.kind == .tilemap) try r.takeInt(u16, .little) else null;
                    _ = tileset_index;
                    if (ase_header.flags.layer_has_uuid) try r.discardAll(16);

                    std.debug.assert(layer_header.kind == .normal);

                    try layers.append(gpa, .{
                        .header = layer_header,
                        .name = name,
                    });
                },

                .cel => {
                    const cel_header = try r.takeStruct(Ase.Cel.Header, .little);
                    std.debug.assert(cel_header.kind == .compressed_img);
                    std.debug.assert(cel_header.z == 0);

                    const extra_header: Ase.Cel.ExtraHeader = switch (cel_header.kind) {
                        .raw => .{ .raw = try r.takeStruct(Ase.Cel.ExtraHeader.Raw, .little) },
                        .linked => .{ .linked = try r.takeStruct(Ase.Cel.ExtraHeader.Linked, .little) },
                        .compressed_img => .{ .compressed_img = try r.takeStruct(Ase.Cel.ExtraHeader.CompressedImg, .little) },
                        .compressed_tilemap => .{ .compressed_tilemap = try r.takeStruct(Ase.Cel.ExtraHeader.CompressedTilemap, .little) },
                    };

                    const pixels = switch (extra_header) {
                        .raw => |eh| blk: {
                            const num_pixels = @as(usize, eh.width) * @as(usize, eh.height);
                            const pixels = try gpa.alloc(u8, num_pixels * ase_header.color_depth.bytesPerPixel());
                            errdefer gpa.free(pixels);

                            try r.readSliceAll(pixels);
                            break :blk pixels;
                        },

                        .linked => @panic("what"),

                        .compressed_img => |eh| blk: {
                            const num_pixels = @as(usize, eh.width) * @as(usize, eh.height);
                            const pixels = try gpa.alloc(u8, num_pixels * ase_header.color_depth.bytesPerPixel());
                            errdefer gpa.free(pixels);

                            try decompress(&r, pixels);
                            break :blk pixels;
                        },

                        .compressed_tilemap => |eh| blk: {
                            std.debug.assert(eh.bits_per_tile == 32);

                            const num_pixels = @as(usize, eh.width) * @as(usize, eh.height);
                            const pixels = try gpa.alloc(u8, num_pixels * (eh.bits_per_tile / 8));
                            errdefer gpa.free(pixels);

                            try decompress(&r, pixels);
                            break :blk pixels;
                        },
                    };

                    try cels.append(gpa, .{
                        .header = cel_header,
                        .extra_header = extra_header,
                        .pixel_data = pixels,
                    });
                },
            }
        }

        // Sort cels
        std.sort.insertion(Ase.Cel, cels.items, {}, struct {
            fn inner(_: void, a: Ase.Cel, b: Ase.Cel) bool {
                const al = @as(isize, a.header.layer) + a.header.z;
                const bl = @as(isize, b.header.layer) + b.header.z;

                return al < bl or (al == bl and (a.header.z < b.header.z));
            }
        }.inner);

        frames.appendAssumeCapacity(.{
            .header = frame_header,
            .cels = try cels.toOwnedSlice(gpa),
        });
    }

    return .{
        .header = ase_header,
        .frames = frames.items,
        .layers = try layers.toOwnedSlice(gpa),
        .palette = palette.?,
    };
}

fn decompress(src: *std.Io.Reader, dst: []u8) !void {
    var src_buf: [std.compress.flate.max_window_len]u8 = undefined;
    var dec = std.compress.flate.Decompress.init(src, .zlib, &src_buf);
    try dec.reader.readSliceAll(dst);

    std.debug.assert(dec.final_block);
}
