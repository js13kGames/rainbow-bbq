const Player = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const render = @import("render.zig");
const mtx = @import("mtx.zig");
const js = @import("js.zig");

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
