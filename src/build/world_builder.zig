const std = @import("std");

const Ase = @import("Ase.zig");

pub const Opcode = struct {
    pub const shape = 0;
    pub const circle = 1;
    pub const entity = 2;
    pub const depth = 3;
    pub const texture = 4;
};

pub const EntityID = struct {
    pub const player = 0;
    pub const grill = 1;
    pub const spawner = 2;
};

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const gpa = init.gpa;
    const io = init.io;

    // File names
    const fname_in = args[1];
    const fname_out = args[2];

    // Read input file
    const ase_src = try cwd.readFileAlloc(io, fname_in, gpa, .unlimited);
    defer gpa.free(ase_src);
    const ase = try Ase.parse(ase_src, gpa);
    defer ase.deinit(gpa);

    // Create output writer
    var out_buf: [1024]u8 = undefined;
    const out_file = try cwd.createFile(io, fname_out, .{});
    var out_w = out_file.writer(io, &out_buf);
    const w = &out_w.interface;
    defer out_file.close(io);

    // Ok, now go through layers
    var prev_depth: u8 = 0;
    for (ase.layers, 0..) |*layer, layer_id| {
        if (std.mem.startsWith(u8, layer.name, "_")) continue;

        // Emit depth opcode
        const depth = getLayerDepth(layer);
        if (std.ascii.startsWithIgnoreCase(layer.name, "texture")) {
            try w.writeByte(Opcode.texture);
            try w.writeByte(depth);
            continue;
        }

        if (depth != prev_depth) {
            try w.writeByte(Opcode.depth);
            try w.writeByte(depth);
            prev_depth = depth;
        }

        // Render layer
        const fb = try gpa.alloc([4]u8, ase.pixelsPerFrame());
        defer gpa.free(fb);
        ase.renderLayer(layer_id, 0, fb);

        // Ok, what kind of layer is this?
        const pixels = try gatherPixels(fb, ase.header.width, gpa);
        defer deinitGathered(pixels);

        if (std.ascii.startsWithIgnoreCase(layer.name, "shapes")) {
            try renderShapeLayer(pixels, w);
        } else if (std.ascii.startsWithIgnoreCase(layer.name, "circle")) {
            try renderCircleLayer(pixels, w);
        } else if (std.ascii.startsWithIgnoreCase(layer.name, "entity")) {
            try renderEntityLayer(pixels, w);
        } else if (std.ascii.startsWithIgnoreCase(layer.name, "texture")) {
            // Yup
        } else {
            std.debug.panic("unknown layer type '{s}'", .{layer.name});
        }
    }

    try out_w.flush();
}

const PixelHashMap = std.AutoHashMap([4]u8, std.ArrayList([2]usize));

fn deinitGathered(pixel_points: *PixelHashMap) void {
    const gpa = pixel_points.allocator;

    var iter = pixel_points.valueIterator();
    while (iter.next()) |val| val.deinit(gpa);
    pixel_points.deinit();
    gpa.destroy(pixel_points);
}

fn gatherPixels(fb: []const [4]u8, width: usize, gpa: std.mem.Allocator) !*PixelHashMap {
    const shape_points = try gpa.create(PixelHashMap);
    shape_points.* = .init(gpa);
    errdefer deinitGathered(shape_points);

    // Go through layer and find all points
    for (fb, 0..) |pixel, i| {
        if (pixel[3] != 255) continue;

        const x = i % width;
        const y = i / width;

        const list = try shape_points.getOrPut(pixel);
        if (!list.found_existing) list.value_ptr.* = .empty;
        try list.value_ptr.append(gpa, .{ x, y });
    }

    // Ok, now build shape from those points
    var iter = shape_points.iterator();
    while (iter.next()) |entry| {
        const list = entry.value_ptr;
        const points = list.items;

        const stats = PointStats.init(points);

        // Sort points
        std.sort.insertion([2]usize, points, stats.middle, struct {
            fn inner(middle_s: @Vector(2, f32), a: [2]usize, b: [2]usize) bool {
                const pfa: @Vector(2, f32) = .{
                    @floatFromInt(a[0]),
                    @floatFromInt(a[1]),
                };
                const pfb: @Vector(2, f32) = .{
                    @floatFromInt(b[0]),
                    @floatFromInt(b[1]),
                };

                const diff_a = middle_s - pfa;
                const diff_b = middle_s - pfb;

                const angle_a = std.math.atan2(diff_a[1], diff_a[0]);
                const angle_b = std.math.atan2(diff_b[1], diff_b[0]);

                return angle_a > angle_b;
            }
        }.inner);
    }

    return shape_points;
}

fn getLayerDepth(layer: *const Ase.Layer) u8 {
    if (layer.name[0] == '_') return 0;

    const depth_str = std.mem.findScalarLast(u8, layer.name, '_') orelse @panic("bad shape layer name");
    const depth = std.fmt.parseInt(u8, layer.name[depth_str + 1 ..], 10) catch @panic("bad shape depth");
    return depth;
}

fn renderShapeLayer(pixel_map: *PixelHashMap, w: *std.Io.Writer) !void {
    var iter = pixel_map.iterator();
    while (iter.next()) |entry| {
        const points = entry.value_ptr.items;

        // Write shape to output stream
        try w.writeByte(Opcode.shape);
        try w.writeByte(@truncate(points.len));
        for (points) |point| {
            try w.writeByte(@truncate(point[0]));
            try w.writeByte(@truncate(point[1]));
        }
    }
}

fn renderCircleLayer(pixel_map: *PixelHashMap, w: *std.Io.Writer) !void {
    // Ok, now build shape from those points
    var iter = pixel_map.iterator();
    while (iter.next()) |entry| {
        const list = entry.value_ptr.items;
        const stats = PointStats.init(list);
        std.debug.assert(stats.width() == stats.height());

        // Write shape to output stream
        try w.writeByte(Opcode.circle);
        try w.writeByte(@round(stats.middle[0]));
        try w.writeByte(@round(stats.middle[1]));
        try w.writeByte(@truncate(stats.width() / 2));
    }
}

fn renderEntityLayer(pixel_map: *PixelHashMap, w: *std.Io.Writer) !void {
    var iter = pixel_map.iterator();
    while (iter.next()) |entry| {
        const color = entry.key_ptr.*;
        const color_u: u32 = @bitCast(color);
        const list = entry.value_ptr.items;

        const entity_id: u8 = switch (color_u) {
            @bitCast([4]u8{ 255, 255, 255, 255 }) => EntityID.player,
            @bitCast([4]u8{ 255, 0, 0, 255 }) => EntityID.grill,
            @bitCast([4]u8{ 0, 0, 255, 255 }) => EntityID.spawner,

            else => std.debug.panic("color {any} does not correspond to any entity!", .{color}),
        };

        for (list) |pos| {
            try w.writeByte(Opcode.entity);
            try w.writeByte(entity_id);
            try w.writeByte(@truncate(pos[0]));
            try w.writeByte(@truncate(pos[1]));
        }
    }
}

const PointStats = struct {
    xmin: usize = std.math.maxInt(usize),
    ymin: usize = std.math.maxInt(usize),
    xmax: usize = 0,
    ymax: usize = 0,

    middle: @Vector(2, f32) = undefined,

    fn init(points: []const [2]usize) PointStats {
        var this: PointStats = .{};

        for (points) |point| {
            this.xmin = @min(this.xmin, point[0]);
            this.ymin = @min(this.ymin, point[1]);
            this.xmax = @max(this.xmax, point[0]);
            this.ymax = @max(this.ymax, point[1]);
        }

        this.middle = .{
            @as(f32, @floatFromInt(this.xmin + this.xmax)) / 2.0,
            @as(f32, @floatFromInt(this.ymin + this.ymax)) / 2.0,
        };

        return this;
    }

    fn width(this: PointStats) usize {
        return this.xmax - this.xmin;
    }

    fn height(this: PointStats) usize {
        return this.ymax - this.ymin;
    }
};
