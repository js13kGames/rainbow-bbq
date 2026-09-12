const std = @import("std");

const mtx = @import("mtx.zig");
const js = @import("js.zig");
const collision = @import("collision.zig");

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

            Opcode.depth => r.seek += 1,

            else => unreachable,
        }
    }

    return .{ num_shapes, num_points };
}

const world_info = collisionDataNum(world_data) catch @panic("how");
pub var world_shapes: [world_info[0]]collision.Polygon = undefined;
var world_points: [world_info[1]]mtx.Vec2 = undefined;

pub noinline fn init() void {
    var r = std.Io.Reader.fixed(world_data);

    var shape_idx: usize = 0;
    var point_idx: usize = 0;

    var z: u8 = 0;

    while (r.seek != r.end) {
        const opcode = r.takeByte() catch unreachable;
        switch (opcode) {
            Opcode.depth => {
                const new_z = r.takeByte() catch unreachable;
                z = new_z;
            },

            Opcode.shape => {
                const num_points = r.takeByte() catch unreachable;

                const points = world_points[point_idx .. point_idx + num_points];
                for (0..num_points) |i| {
                    points[i] = readPos(&r);
                }

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

                world_shapes[shape_idx] = .initCircle(
                    .init(pos[0], pos[1], 0),
                    points,
                    @floatFromInt(z),
                    radius,
                );
                shape_idx += 1;
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

fn readPos(r: *std.Io.Reader) @Vector(2, f32) {
    return .{
        @as(f32, @floatFromInt(r.takeByte() catch unreachable)) * 32 - 1024,
        @as(f32, @floatFromInt(r.takeByte() catch unreachable)) * 32 - 1024,
    };
}
