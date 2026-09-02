const std = @import("std");

const Ase = @import("Ase.zig");
const gbcompress = @import("gbcompress.zig");

const atlas_w = 512;
const atlas_h = 512;

const Folder = struct {
    name: []const u8 = "",
    parent: ?*Folder = null,

    images: []*Image,
    children: []*Folder,

    fn deinit(this: *const Folder, gpa: std.mem.Allocator) void {
        gpa.free(this.name);
        gpa.free(this.images);

        for (this.children) |*child| child.deinit(gpa);
        gpa.free(this.children);
    }
};

const ColorError = error{
    TooManyColors,
};

const Image = struct {
    name: []const u8,
    folder: *Folder,

    w: usize,
    h: usize,
    palette: []const [4]u8,
    frames: []Frame,

    fn deinit(this: *const Image, gpa: std.mem.Allocator) void {
        gpa.free(this.name);
        gpa.free(this.palette);

        for (this.frames) |*frame| frame.deinit(gpa);
        gpa.free(this.frames);
    }

    fn determineColors(this: *const Image) ?[2][4]u8 {
        var colors: ?[2][4]u8 = null;

        for (this.frames, 0..) |*frame, i| {
            const frame_colors = frame.determineColors() catch {
                std.log.err("frame {d} of sprite '{s}' has more than 2 colors!", .{ i, this.name });
                has_errors = true;
                continue;
            };

            if (colors) |c| {
                // Frames use different colors... oh well
                if (!std.meta.eql(c, frame_colors)) return null;
            } else {
                colors = frame_colors;
            }
        }

        return colors;
    }
};

const Frame = struct {
    pixels: []const [4]u8,
    frame_time: usize,
    x: usize = 0,
    y: usize = 0,

    fn deinit(this: *const Frame, gpa: std.mem.Allocator) void {
        gpa.free(this.pixels);
    }

    fn determineColors(this: *const Frame) ColorError![2][4]u8 {
        var colors: [2][4]u8 = .{ .{ 255, 255, 255, 255 }, .{ 0, 0, 0, 255 } };
        var seen: usize = 0;

        // Loop through pixels and find colors
        px: for (this.pixels) |pixel| {
            // find existing color
            for (0..seen) |c| {
                if (std.meta.eql(pixel, colors[c])) {
                    continue :px;
                }
            }

            // Color has not been seen before...
            if (seen >= colors.len) return ColorError.TooManyColors;
            colors[seen] = pixel;
            seen += 1;
        }

        // Swap colors if last one is darker or transparent
        if (seen == 2) {
            const max_bright_0 = @max(colors[0][0], colors[0][1], colors[0][2]);
            const max_bright_1 = @max(colors[1][0], colors[1][1], colors[1][2]);
            const must_swap = colors[1][3] == 0 or (max_bright_1 > max_bright_0 and colors[0][3] != 0);
            if (must_swap) {
                const temp = colors[0];
                colors[0] = colors[1];
                colors[1] = temp;
            }
        }

        return colors;
    }
};

var io: std.Io = undefined;

pub fn walkDir(
    dir: std.Io.Dir,
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    all_images: *std.ArrayList(*Image),
) !*Folder {
    var dir_iter = dir.iterate();

    const self_folder = try arena.create(Folder);

    var images = std.ArrayList(*Image).empty;
    errdefer images.deinit(gpa);
    var folders = std.ArrayList(*Folder).empty;
    errdefer folders.deinit(gpa);

    while (try dir_iter.next(io)) |entry| {
        switch (entry.kind) {
            .file => {
                if (!std.ascii.endsWithIgnoreCase(entry.name, ".aseprite") and
                    !std.ascii.endsWithIgnoreCase(entry.name, ".ase"))
                {
                    continue;
                }

                const file = try dir.readFileAlloc(io, entry.name, gpa, .unlimited);
                defer gpa.free(file);
                const ase = try Ase.parse(file, gpa);
                defer ase.deinit(gpa);

                var frames = try arena.alloc(Frame, ase.frames.len);
                for (ase.frames, 0..) |*ase_frame, i| {
                    const pixels = try arena.alloc([4]u8, ase.pixelsPerFrame());
                    ase.renderFrame(i, pixels);
                    frames[i] = .{
                        .frame_time = ase_frame.header.frame_duration,
                        .pixels = pixels,
                    };
                }

                const image = try arena.create(Image);
                image.* = .{
                    .name = try arena.dupe(u8, entry.name),
                    .folder = self_folder,
                    .palette = try arena.dupe([4]u8, ase.palette),
                    .frames = frames,

                    .w = ase.header.width,
                    .h = ase.header.height,
                };

                try all_images.append(gpa, image);
                try images.append(gpa, image);
            },

            .directory => {
                const child_dir = try dir.openDir(io, entry.name, .{ .iterate = true });
                defer child_dir.close(io);

                var folder = try walkDir(child_dir, gpa, arena, all_images);
                folder.name = try arena.dupe(u8, entry.name);
                folder.parent = self_folder;
                try folders.append(gpa, folder);
            },

            else => {
                @panic("unimplemented");
            },
        }
    }

    self_folder.children = try transferList(*Folder, &folders, gpa, arena);
    self_folder.images = try transferList(*Image, &images, gpa, arena);
    return self_folder;
}

fn transferList(
    comptime T: type,
    list: *std.ArrayList(T),
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
) ![]T {
    const duped = try arena.dupe(T, list.items);
    list.clearAndFree(gpa);
    return duped;
}

var has_errors = false;

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const cwd = std.Io.Dir.cwd();
    io = init.io;
    const gpa = init.gpa;

    var all_images = std.ArrayList(*Image).empty;
    defer all_images.deinit(gpa);

    // Find all input files
    const dir = try cwd.openDir(io, args[1], .{ .iterate = true });
    const root_folder = try walkDir(dir, gpa, arena, &all_images);

    // Sort images by size
    std.sort.insertion(*Image, all_images.items, {}, struct {
        fn inner(_: void, a: *Image, b: *Image) bool {
            const al = a.w * a.h;
            const bl = b.w * b.w;

            return al > bl;
        }
    }.inner);

    // Create atlas
    var bin_root = BinPack{ .w = atlas_w, .h = atlas_h };
    for (all_images.items) |image| {
        for (image.frames) |*frame| {
            const bin = (try bin_root.fit(image, arena)).?;
            frame.x = bin.x;
            frame.y = bin.y;
        }
    }

    // Render output image
    std.debug.assert(atlas_w % 8 == 0);
    const atlas_buffer = try arena.alloc(u8, atlas_w * atlas_h / 8);
    @memset(atlas_buffer, 0);
    const atlas = BitAtlas{
        .buffer = atlas_buffer,
        .w = atlas_w,
        .h = atlas_h,
    };
    renderAtlas(atlas, all_images.items);

    const atlas_fname = args[2];
    var comp_w = std.Io.Writer.Allocating.init(arena);
    try gbcompress.compress(atlas.buffer, &comp_w.writer);
    try cwd.writeFile(io, .{
        .sub_path = atlas_fname,
        .data = comp_w.written(),
    });

    const compress_sanity_check = try arena.alloc(u8, atlas_w * atlas_h / 8);
    try gbcompress.decompress(comp_w.written(), compress_sanity_check);
    std.debug.assert(std.mem.eql(u8, atlas.buffer, compress_sanity_check));

    // Write map file
    var writer_list = std.Io.Writer.Allocating.init(gpa);
    defer writer_list.deinit();
    const w_list = &writer_list.writer;

    var writer_structured = std.Io.Writer.Allocating.init(gpa);
    defer writer_structured.deinit();
    const w_structured = &writer_structured.writer;

    // Write sprite header
    try w_list.writeAll(
        \\//! auto generated
        \\
        \\const Sprite = @This();
        \\
        \\
    );

    try w_list.print("pub const atlas_width = {};\n", .{atlas_w / 8});
    try w_list.print("pub const atlas_height = {};\n\n", .{atlas_h});

    try w_list.writeAll(
        \\u0: f32,
        \\v0: f32,
        \\u1: f32,
        \\v1: f32,
        \\
        \\/// If this sprite is an animation, this can be used to get a specific frame.
        \\/// It is on you to know how many frames a sprite has.
        \\pub inline fn frame(this: *const Sprite, index: usize) *const Sprite {
        \\    return @ptrFromInt(@intFromPtr(this) + @sizeOf(Sprite) * index);
        \\}
        \\
        \\pub const Colors = struct {
        \\    back: [4]u8,
        \\    fore: [4]u8,
        \\};
        \\
        \\const _list = [_]Sprite{
        \\
    );

    // Loop de loop
    var ow = OutWriter{
        .list = w_list,
        .structured = w_structured,
        .atlas_w = @as(f32, @floatFromInt(bin_root.w)),
        .atlas_h = @as(f32, @floatFromInt(bin_root.h)),
    };
    try ow.writeFolder(root_folder, 0);

    // End of list
    try w_list.writeAll("};\n\n");

    // Output this to a file
    const map_fname = args[3];
    const map_file = try cwd.createFile(io, map_fname, .{});
    defer map_file.close(io);
    try map_file.writeStreamingAll(io, writer_list.written());
    try map_file.writeStreamingAll(io, writer_structured.written());

    if (has_errors) {
        return error.InvalidSprites;
    }
}

pub fn renderAtlas(atlas: BitAtlas, images: []const *const Image) void {
    for (images) |image| {
        for (image.frames) |*frame| {
            const colors = frame.determineColors() catch continue;

            for (0..image.h) |sy| {
                for (0..image.w) |sx| {
                    const src_color = frame.pixels[sx + sy * image.w];

                    const bit = !std.meta.eql(src_color, colors[0]);
                    atlas.set(frame.x + sx, frame.y + sy, bit);
                }
            }
        }
    }
}

const BitAtlas = struct {
    buffer: []u8,
    w: usize,
    h: usize,

    pub fn set(this: BitAtlas, x: usize, y: usize, bit: bool) void {
        const idx = x + y * this.w;
        const byte_idx = idx / 8;
        const bit_idx: u3 = @truncate(idx % 8);

        if (bit) {
            this.buffer[byte_idx] |= @as(u8, 1) << bit_idx;
        } else {
            this.buffer[byte_idx] &= ~(@as(u8, 1) << bit_idx);
        }
    }
};

const OutWriter = struct {
    list: *std.Io.Writer,
    structured: *std.Io.Writer,
    seen: usize = 0,

    atlas_w: f32,
    atlas_h: f32,

    pub fn writeFolder(this: *OutWriter, folder: *const Folder, depth: usize) !void {
        // First write sprites
        for (folder.images) |image| {
            const self_index = this.seen;
            defer this.seen += image.frames.len;

            // Write frames to the sprite list
            for (image.frames) |*frame| {
                const tc_u0 = @as(f32, @floatFromInt(frame.x)) / this.atlas_w;
                const tc_v0 = @as(f32, @floatFromInt(frame.y)) / this.atlas_h;

                const tc_u1 = @as(f32, @floatFromInt(frame.x + image.w)) / this.atlas_w;
                const tc_v1 = @as(f32, @floatFromInt(frame.y + image.h)) / this.atlas_h;

                try this.list.print("    .{{ .u0 = {}, .v0 = {}, .u1 = {}, .v1 = {} }},\n", .{
                    tc_u0,
                    tc_v0,
                    tc_u1 - 0.00001,
                    tc_v1 - 0.00001,
                });
            }

            // Write hierarchy thing
            const sprite_name = image.name[0..(std.mem.findScalar(u8, image.name, '.') orelse image.name.len)];

            for (0..depth) |_| try this.structured.writeAll("    ");
            try this.structured.print("pub const {s} = struct {{\n", .{sprite_name});

            for (0..depth + 1) |_| try this.structured.writeAll("    ");
            try this.structured.print("pub const w = {};\n", .{image.w});

            for (0..depth + 1) |_| try this.structured.writeAll("    ");
            try this.structured.print("pub const h = {};\n", .{image.h});

            for (0..depth + 1) |_| try this.structured.writeAll("    ");
            try this.structured.print("pub const frames = {};\n", .{image.frames.len});

            for (0..depth + 1) |_| try this.structured.writeAll("    ");
            try this.structured.print("pub const spr = &_list[{}];\n", .{self_index});

            if (image.determineColors()) |colors| {
                for (0..depth + 1) |_| try this.structured.writeAll("    ");
                try this.structured.writeAll("pub const colors = Colors{\n");

                for (0..depth + 2) |_| try this.structured.writeAll("    ");
                try this.structured.print(".back = .{{ {}, {}, {}, {} }},\n", .{
                    colors[0][0],
                    colors[0][1],
                    colors[0][2],
                    colors[0][3],
                });

                for (0..depth + 2) |_| try this.structured.writeAll("    ");
                try this.structured.print(".fore = .{{ {}, {}, {}, {} }},\n", .{
                    colors[1][0],
                    colors[1][1],
                    colors[1][2],
                    colors[1][3],
                });

                for (0..depth + 1) |_| try this.structured.writeAll("    ");
                try this.structured.writeAll("};\n\n");
            } else {
                for (0..depth + 1) |_| try this.structured.writeAll("    ");
                try this.structured.writeAll("pub const colors = @compileError(\"sprite frames have different colors\");\n\n");
            }

            for (0..depth + 1) |_| try this.structured.writeAll("    ");
            try this.structured.writeAll("pub const frame_colors = [_]Colors{\n");

            for (image.frames) |frame| {
                const colors = frame.determineColors() catch continue;

                for (0..depth + 2) |_| try this.structured.writeAll("    ");
                try this.structured.writeAll(".{\n");

                for (0..depth + 3) |_| try this.structured.writeAll("    ");
                try this.structured.print(".back = .{{ {}, {}, {}, {} }},\n", .{
                    colors[0][0],
                    colors[0][1],
                    colors[0][2],
                    colors[0][3],
                });

                for (0..depth + 3) |_| try this.structured.writeAll("    ");
                try this.structured.print(".fore = .{{ {}, {}, {}, {} }},\n", .{
                    colors[1][0],
                    colors[1][1],
                    colors[1][2],
                    colors[1][3],
                });

                for (0..depth + 2) |_| try this.structured.writeAll("    ");
                try this.structured.writeAll("},\n");
            }

            for (0..depth + 1) |_| try this.structured.writeAll("    ");
            try this.structured.writeAll("};\n");

            for (0..depth) |_| try this.structured.writeAll("    ");
            try this.structured.print("}};\n", .{});
        }

        // Now write sub folders
        for (folder.children, 0..) |child, i| {
            if (folder.images.len != 0 or i != 0) try this.structured.writeByte('\n');

            for (0..depth) |_| try this.structured.writeAll("    ");
            try this.structured.print("pub const {s} = struct {{\n", .{child.name});

            try this.writeFolder(child, depth + 1);

            for (0..depth) |_| try this.structured.writeAll("    ");
            try this.structured.writeAll("};\n");
        }
    }
};

const BinPack = struct {
    x: usize = 0,
    y: usize = 0,
    w: usize,
    h: usize,
    image: ?*const Image = null,

    right: ?*BinPack = null,
    down: ?*BinPack = null,

    pub fn fit(root: *BinPack, image: *const Image, arena: std.mem.Allocator) !?*BinPack {
        const node = root.findNode(image) orelse return error.NoMoreSpace;
        try node.splitNode(image, arena);
        return node;
    }

    pub fn findNode(node: *BinPack, image: *const Image) ?*BinPack {
        if (node.image != null) {
            return node.right.?.findNode(image) orelse node.down.?.findNode(image);
        }

        if (image.w <= node.w and image.h <= node.h) {
            return node;
        }

        return null;
    }

    pub fn splitNode(node: *BinPack, image: *const Image, arena: std.mem.Allocator) !void {
        node.image = image;

        const down = try arena.create(BinPack);
        down.* = .{
            .x = node.x,
            .y = node.y + image.h,
            .w = node.w,
            .h = node.h - image.h,
        };
        node.down = down;

        const right = try arena.create(BinPack);
        right.* = .{
            .x = node.x + image.w,
            .y = node.y,
            .w = node.w - image.w,
            .h = node.h,
        };
        node.right = right;
    }
};
