const Player = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const render = @import("render.zig");
const mtx = @import("mtx.zig");
const js = @import("js.zig");
const collision = @import("collision.zig");

position: mtx.Vector = .init(0, 0, @as(f32, Sprite.unicorn.h) / 2.0),
speed: mtx.Vector = .init(0, 0, 0),

const move_accel: f32 = 0.035;
const max_speed = 1.5;

pub fn update(this: *Player) void {
    // Build movement vector
    const target_direction = render.camera.yaw_rad;
    const added_speed = mtx.Vector.init(0, move_accel, 0).rotateZ(target_direction);

    // Add to current speed
    this.speed = this.speed.add4(added_speed);

    // Cap speed
    const speed_var = this.speed.length();
    if (speed_var > max_speed) {
        const speed_direction = this.speed.normalize3();
        this.speed = speed_direction.mulScalar(max_speed);
    }

    // Ok, now update position
    if (!js.input.keys[' '].isHeld()) {
        this.position = this.position.add4(this.speed);

        const width = 7;
        const height = 16;

        var points: [8]mtx.Vec2 = undefined;
        for (&points, 0..) |*point, i| {
            const angle = if (i == 0) 0.0 else std.math.tau / @as(f32, @floatFromInt(i));

            point.* = .{
                this.position.v[0] + js.cos(angle) * width,
                this.position.v[1] + js.sin(angle) * width,
            };
        }

        var shape = collision.Polygon{
            .points = &points,
            .z_min = 0,
            .z_max = height,
            .middle = .{ this.position.v[0], this.position.v[1] },
        };

        while (collision.collideWithWorld(&shape)) |eject| {
            shape.move(.init(
                eject.pen_dir[0] * (eject.pen_length + 0.001),
                eject.pen_dir[1] * (eject.pen_length + 0.001),
                0,
            ));
        }

        this.position.v[0] = shape.middle.?[0];
        this.position.v[1] = shape.middle.?[1];
    }

    // Move camera
    const camera_distance_h = 50;
    const camera_distance_v = 10;
    render.camera.position = this.position.add4(
        mtx.Vector
            .init(0, -camera_distance_h, camera_distance_v)
            .rotateX(render.camera.pitch_rad)
            .rotateZ(render.camera.yaw_rad),
    );
    render.camera.position.v[3] = 1;
}

pub fn draw(this: *const Player) void {
    // Render the thing
    const sprite = Sprite.unicorn;
    render.drawQuad(sprite.spr, .fromAtlas(sprite, .{
        .pos = .{ this.position.v[0], this.position.v[1], this.position.v[2] },
        .rot = .{ 0, 0, render.camera.yaw_rad },
    }));
}
