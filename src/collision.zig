//! File responsible for collisions and physics.
//!
//! Sources:
//! https://timallanwheeler.com/blog/2024/08/01/2d-collision-detection-and-resolution/
//! https://github.com/OneLoneCoder/Javidx9/blob/master/PixelGameEngine/SmallerProjects/OneLoneCoder_PGE_PolygonCollisions1.cpp

const std = @import("std");

const mtx = @import("mtx.zig");
const js = @import("js.zig");

pub const gravity: f32 = 0.115;

/// Convex polygon.
/// Concave polygons will not work.
pub const Polygon = struct {
    points: []mtx.Vec2,
    z_min: f32,
    z_max: f32,

    middle: mtx.Vec2 = undefined,

    pub fn move(this: *Polygon, delta: mtx.Vector) void {
        this.z_min += delta.v[2];
        this.z_max += delta.v[2];

        this.middle[0] += delta.v[0];
        this.middle[1] += delta.v[1];

        for (0..this.points.len) |i| {
            this.points[i][0] += delta.v[0];
            this.points[i][1] += delta.v[1];
        }
    }

    pub fn calculateMiddle(this: *Polygon) void {
        var xmin = std.math.inf(f32);
        var ymin = std.math.inf(f32);
        var xmax = -std.math.inf(f32);
        var ymax = -std.math.inf(f32);

        for (this.points) |point| {
            xmin = @min(xmin, point[0]);
            ymin = @min(ymin, point[1]);
            xmax = @max(xmax, point[0]);
            ymax = @max(ymax, point[1]);
        }

        this.middle = .{ (xmin + xmax) / 2.0, (ymin + ymax) / 2.0 };
    }

    pub fn buildCircle(this: *Polygon, x: f32, y: f32, z: f32, height: f32, radius: f32) void {
        for (this.points, 0..) |*point, i| {
            const angle = (std.math.tau / 8.0) * @as(f32, @floatFromInt(i));

            point.* = .{
                x + js.cos(angle) * radius,
                y + js.sin(angle) * radius,
            };
        }

        this.z_min = z;
        this.z_max = z + height;
        this.middle = .{ x, y };
    }
};

const PolygonProjection = struct {
    min: f32 = std.math.inf(f32),
    max: f32 = -std.math.inf(f32),
};

const CollisionResult = struct {
    pen_length: f32 = std.math.inf(f32),
    pen_dir: mtx.Vec2 = .{ std.math.nan(f32), std.math.nan(f32) },
    floor: f32 = 0,
};

fn projectPolygon(poly: *const Polygon, axis_proj: mtx.Vec2) PolygonProjection {
    var proj = PolygonProjection{};
    for (poly.points) |point| {
        const q = mtx.dot2D(point, axis_proj);

        proj.min = @min(proj.min, q);
        proj.max = @max(proj.max, q);
    }

    return proj;
}

fn shapeOverlapSATInner(poly_1: *const Polygon, poly_2: *const Polygon) ?CollisionResult {
    var point_b = poly_1.points[poly_1.points.len - 1];
    var result = CollisionResult{};

    for (poly_1.points) |point_a| {
        defer point_b = point_a;

        const axis_proj = mtx.Vec2{
            -(point_b[1] - point_a[1]),
            point_b[0] - point_a[0],
        };

        const proj_1 = projectPolygon(poly_1, axis_proj);
        const proj_2 = projectPolygon(poly_2, axis_proj);

        // If there is a gap, we have a collision on our hands
        if (!(proj_2.max >= proj_1.min and proj_1.max >= proj_2.min)) {
            return null;
        }

        const nlen = mtx.len2D(axis_proj);
        const penetration_len = @min(
            @abs(proj_1.min - proj_2.max),
            @abs(proj_1.max - proj_2.min),
        ) / nlen;
        if (penetration_len < result.pen_length) {
            result.pen_length = penetration_len;
            result.pen_dir = .{ axis_proj[0] / nlen, axis_proj[1] / nlen };
            result.floor = @min(
                poly_1.z_max,
                poly_2.z_max,
            );
        }
    }

    return result;
}

pub fn shapeOverlapSAT(a: *const Polygon, b: *const Polygon) ?CollisionResult {
    if (a.z_min > b.z_max or a.z_max < b.z_min) return null;
    const result_a = shapeOverlapSATInner(a, b) orelse return null;
    const result_b = shapeOverlapSATInner(b, a) orelse return null;

    const shortest = if (result_a.pen_length <= result_b.pen_length) result_a else result_b;

    const between_vec = mtx.Vec2{
        b.middle[0] - a.middle[0],
        b.middle[1] - a.middle[1],
    };

    // Ok, now check the thing
    return if (mtx.dot2D(between_vec, shortest.pen_dir) > 0) shortest else .{
        .pen_length = shortest.pen_length,
        .floor = shortest.floor,
        .pen_dir = .{
            -shortest.pen_dir[0],
            -shortest.pen_dir[1],
        },
    };
}

const PolyDescriptor = struct {
    z_min: f32,
    z_max: f32,
    points: []const mtx.Vec2,
};

const polys = [_]PolyDescriptor{
    .{
        .z_min = 0,
        .z_max = 24,
        .points = &[_]mtx.Vec2{
            .{ 40 * 5, 40 * 5 },
            .{ 50 * 5, 40 * 5 },
            .{ 60 * 5, 50 * 5 },
            .{ 65 * 5, 70 * 5 },
            .{ 40 * 5, 80 * 5 },
            .{ 20 * 5, 60 * 5 },
        },
    },
    .{
        .z_min = 0,
        .z_max = 24,
        .points = &[_]mtx.Vec2{
            .{ 60 * 5, 40 * 5 },
            .{ 70 * 5, 30 * 5 },
            .{ 75 * 5, 45 * 5 },
        },
    },
    .{
        .z_min = -64,
        .z_max = 0,
        .points = &[_]mtx.Vec2{
            .{ 512, 512 },
            .{ -512, 512 },
            .{ -512, -512 },
            .{ 512, -512 },
        },
    },

    // Surrounding walls
    .{
        .z_min = 0,
        .z_max = 128,
        .points = &[_]mtx.Vec2{
            .{ 512, 512 },
            .{ 512, -512 },
            .{ 1024, -512 },
            .{ 1024, 512 },
        },
    },
    .{
        .z_min = 0,
        .z_max = 128,
        .points = &[_]mtx.Vec2{
            .{ -512, 512 },
            .{ -512, -512 },
            .{ -1024, -512 },
            .{ -1024, 512 },
        },
    },
    .{
        .z_min = 0,
        .z_max = 128,
        .points = &[_]mtx.Vec2{
            .{ 512, 512 },
            .{ -512, 512 },
            .{ -512, 1024 },
            .{ 512, 1024 },
        },
    },
    .{
        .z_min = 0,
        .z_max = 128,
        .points = &[_]mtx.Vec2{
            .{ 512, -512 },
            .{ -512, -512 },
            .{ -512, -1024 },
            .{ 512, -1024 },
        },
    },
};

pub fn initWorld() void {
    const num_points = comptime num_points: {
        var num_points: usize = 0;
        for (&polys) |*poly| {
            num_points += poly.points.len;
        }
        break :num_points num_points;
    };

    const mem = js.staticAlloc(mtx.Vec2, num_points);
    var p: usize = 0;
    for (&polys, &world_walls) |poly, *wall| {
        const points = mem[p .. p + poly.points.len];
        p += poly.points.len;

        @memcpy(points, poly.points);
        wall.z_min = poly.z_min;
        wall.z_max = poly.z_max;
        wall.points = points;
        wall.calculateMiddle();
    }
}

pub var world_walls: [polys.len]Polygon = undefined;

pub fn collideWithWorld(this: *Polygon) ?CollisionResult {
    for (&world_walls) |*wall| {
        if (shapeOverlapSAT(wall, this)) |result| {
            return result;
        }
    }

    return null;
}

pub fn isOnFloor(a: *const Polygon) bool {
    var shape_copy = a.*;
    shape_copy.z_min -= 1;
    shape_copy.z_max -= 1;

    return collideWithWorld(&shape_copy) != null;
}
