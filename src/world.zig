const std = @import("std");
const Sprite = @import("Sprite");

const mtx = @import("mtx.zig");
const js = @import("js.zig");
const collision = @import("collision.zig");
const Entity = @import("Entity.zig");
const render = @import("render.zig");

const world_builder = @import("build/world_builder.zig");
const Opcode = world_builder.Opcode;

const GeomOpcode = enum(u8) {
    circle,
    aabb,
};

const world_data = @embedFile("world.bin");

pub fn collisionDataNum(comptime data: []const u8) !struct { usize, usize } {
    var num_shapes: usize = 0;
    var num_points: usize = 0;

    var r = std.Io.Reader.fixed(data);
    while (r.seek != r.end) {
        const opcode = try r.takeByte();

        switch (opcode) {
            Opcode.shape => {
                const shape_points = try r.takeByte();
                r.seek += shape_points;
                r.seek += shape_points;

                num_points += shape_points;
                num_shapes += 1;
            },

            Opcode.circle => {
                r.seek += 3;
                num_points += 16;
                num_shapes += 1;
            },

            Opcode.entity => r.seek += 3,
            Opcode.depth, Opcode.texture => r.seek += 1,

            else => unreachable,
        }
    }

    return .{ num_shapes, num_points };
}

pub const SpriteColor = struct {
    sprite: *const Sprite,
    colors: Sprite.Colors,
};

pub const ShapeTexture = struct {
    top: SpriteColor,
    side: SpriteColor,
};

const world_info = collisionDataNum(world_data) catch @panic("how");
var world_points: [world_info[1]]mtx.Vec2 = undefined;
pub var world_shapes: [world_info[0]]collision.Polygon = undefined;
pub var world_texture: [world_info[0]]ShapeTexture = undefined;

const spawner_table = [_]*const fn (entity: *Entity, pos: mtx.Vector) void{
    Entity.Player.init,
    Entity.Grill.init,
    Entity.Spawner.init,
};

fn darkenColor(color: u32) u32 {
    var out: [4]u8 = @bitCast(color);
    for (0..3) |i| {
        var fcol: f32 = @floatFromInt(out[i]);
        fcol *= 0.8;
        out[i] = @trunc(fcol);
    }

    return @bitCast(out);
}

fn darkenColorPair(colors: Sprite.Colors) Sprite.Colors {
    return .{
        .fore = darkenColor(colors.fore),
        .back = darkenColor(colors.back),
    };
}

const texture_table = [_]ShapeTexture{
    // Black void
    .{
        .top = .{ .sprite = Sprite.arrow.spr, .colors = .{ .fore = render.buildColor(.{ 0, 0, 0, 255 }), .back = render.buildColor(.{ 0, 0, 0, 255 }) } },
        .side = .{ .sprite = Sprite.arrow.spr, .colors = .{ .fore = render.buildColor(.{ 0, 0, 0, 255 }), .back = render.buildColor(.{ 0, 0, 0, 255 }) } },
    },
    // stone + grass
    .{
        .top = .{ .sprite = Sprite.grass.spr, .colors = Sprite.grass.colors },
        .side = .{ .sprite = Sprite.stone.spr, .colors = darkenColorPair(Sprite.stone.colors) },
    },
    // stone + stone
    .{
        .top = .{ .sprite = Sprite.stone.spr, .colors = Sprite.stone.colors },
        .side = .{ .sprite = Sprite.stone.spr, .colors = darkenColorPair(Sprite.stone.colors) },
    },
    // pillar + grass
    .{
        .top = .{ .sprite = Sprite.grass.spr, .colors = Sprite.grass.colors },
        .side = .{ .sprite = Sprite.pillar.spr, .colors = Sprite.pillar.colors },
    },
    // Invisible
    .{
        .top = .{ .sprite = Sprite.arrow.spr, .colors = .{ .fore = 0, .back = 0 } },
        .side = .{ .sprite = Sprite.arrow.spr, .colors = .{ .fore = 0, .back = 0 } },
    },
};

pub noinline fn init() void {
    var r = std.Io.Reader.fixed(world_data);

    var texture_idx: usize = 0;
    var shape_idx: usize = 0;
    var point_idx: usize = 0;
    var z: u8 = 0;

    while (r.seek != r.end) {
        const opcode = r.takeByte() catch unreachable;
        switch (opcode) {
            Opcode.depth => {
                z = r.takeByte() catch unreachable;
            },

            Opcode.texture => {
                texture_idx = r.takeByte() catch unreachable;
            },

            Opcode.shape => {
                const num_points = r.takeByte() catch unreachable;

                const points = world_points[point_idx .. point_idx + num_points];
                for (0..num_points) |i| {
                    points[i] = readPos(&r);
                }

                world_texture[shape_idx] = texture_table[texture_idx];
                world_shapes[shape_idx] = .{
                    .points = points,
                    .z_min = 0,
                    .z_max = @floatFromInt(z),
                };
                world_shapes[shape_idx].calculateMiddle();

                shape_idx += 1;
                point_idx += num_points;
            },

            Opcode.circle => {
                const pos = readPos(&r);
                const radius_i: usize = r.takeByte() catch unreachable;
                const radius: f32 = @floatFromInt(radius_i * 32);

                const points = world_points[point_idx .. point_idx + 16];
                point_idx += 16;

                world_texture[shape_idx] = texture_table[texture_idx];
                world_shapes[shape_idx] = .initCircle(
                    .init(pos[0], pos[1], 0),
                    points,
                    @floatFromInt(z),
                    radius,
                );
                shape_idx += 1;
            },

            Opcode.entity => {
                const entity_id = r.takeByte() catch unreachable;
                const pos = readPos(&r);

                const entity = Entity.findFree().?;
                spawner_table[entity_id](entity, .init(pos[0], pos[1], @as(f32, @floatFromInt(z)) + 0.01));
            },

            else => unreachable,
        }
    }

    // Force first shape to extend further
    const first_shape = &world_shapes[0];
    first_shape.z_min = -6000;
    first_shape.z_max = -0.1;

    std.debug.assert(shape_idx == world_shapes.len);
    std.debug.assert(point_idx == world_points.len);
}

const img_width: f32 = 64;
pub const level_size: f32 = 1500;
const coord_scale: f32 = level_size / img_width;

fn readPos(r: *std.Io.Reader) @Vector(2, f32) {
    return .{
        @as(f32, @floatFromInt(r.takeByte() catch unreachable)) * coord_scale,
        @as(f32, @floatFromInt(r.takeByte() catch unreachable)) * coord_scale,
    };
}
