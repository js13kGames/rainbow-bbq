//! Sources:
//! https://timallanwheeler.com/blog/2024/08/01/2d-collision-detection-and-resolution/
//! https://github.com/OneLoneCoder/Javidx9/blob/master/PixelGameEngine/SmallerProjects/OneLoneCoder_PGE_PolygonCollisions1.cpp

const std = @import("std");

const mtx = @import("mtx.zig");

/// Convex polygon.
/// Concave polygons will not work.
pub const Polygon = struct {
    points: []mtx.Vec2,
    z_min: f32,
    z_max: f32,

    middle: ?mtx.Vec2 = null,

    pub fn move(this: *Polygon, delta: mtx.Vector) void {
        this.z_min += delta.v[2];
        this.z_max += delta.v[2];

        if (this.middle) |*middle| {
            middle[0] += delta.v[0];
            middle[1] += delta.v[1];
        }

        for (0..this.points.len) |i| {
            this.points[i][0] += delta.v[0];
            this.points[i][1] += delta.v[1];
        }
    }

    pub fn getMiddle(this: *Polygon) mtx.Vec2 {
        if (this.middle) |middle| return middle;

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

        const middle = .{ (xmin + xmax) / 2.0, (ymin + ymax) / 2.0 };
        this.middle = middle;
        return middle;
    }
};

const PolygonProjection = struct {
    min: f32 = std.math.inf(f32),
    max: f32 = -std.math.inf(f32),
};

const CollisionResult = struct {
    pen_length: f32 = std.math.inf(f32),
    pen_dir: mtx.Vec2 = .{ std.math.nan(f32), std.math.nan(f32) },
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
        }
    }

    return result;
}

pub fn shapeOverlapSAT(a: *Polygon, b: *Polygon) ?CollisionResult {
    const result_a = shapeOverlapSATInner(a, b) orelse return null;
    const result_b = shapeOverlapSATInner(b, a) orelse return null;

    const shortest = if (result_a.pen_length <= result_b.pen_length) result_a else result_b;

    const mid_a = a.getMiddle();
    const mid_b = b.getMiddle();

    const between_vec = mtx.Vec2{
        mid_b[0] - mid_a[0],
        mid_b[1] - mid_a[1],
    };

    // Ok, now check the thing
    return if (mtx.dot2D(between_vec, shortest.pen_dir) > 0) shortest else .{
        .pen_length = shortest.pen_length,
        .pen_dir = .{
            -shortest.pen_dir[0],
            -shortest.pen_dir[1],
        },
    };
}

pub var world_walls: []Polygon = @constCast(&[_]Polygon{
    .{
        .z_min = 0,
        .z_max = 24,
        .points = @constCast(&[_]mtx.Vec2{
            .{ 40 * 5, 40 * 5 },
            .{ 50 * 5, 40 * 5 },
            .{ 60 * 5, 50 * 5 },
            .{ 65 * 5, 70 * 5 },
            .{ 40 * 5, 80 * 5 },
            .{ 20 * 5, 60 * 5 },
        }),
    },
    .{
        .z_min = 0,
        .z_max = 24,
        .points = @constCast(&[_]mtx.Vec2{
            .{ 60 * 5, 40 * 5 },
            .{ 70 * 5, 30 * 5 },
            .{ 75 * 5, 45 * 5 },
        }),
    },
});

pub fn collideWithWorld(this: *Polygon) ?CollisionResult {
    for (world_walls) |*wall| {
        if (shapeOverlapSAT(wall, this)) |result| {
            return result;
        }
    }

    return null;
}
