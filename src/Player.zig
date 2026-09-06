const Player = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const render = @import("render.zig");
const mtx = @import("mtx.zig");
const js = @import("js.zig");
const collision = @import("collision.zig");

body: collision.PhysicsEntity,
points: [8]mtx.Vec2 = undefined,

/// Singleton instance
pub var player: Player = undefined;

const move_accel: f32 = 0.035;
const max_speed = 1.6;

const player_width = 7;
const player_height = 16;

pub fn init(this: *Player, pos: mtx.Vector) void {
    this.body.position = pos;
    this.body.speed = .init(0, 0, 0);
    this.body.shape.points = &this.points;
    this.body.shape.buildCircle(pos.v[0], pos.v[1], pos.v[2], player_height / 2.0, player_width);
}

pub fn update(this: *Player) void {
    // Build movement vector
    const target_direction = render.camera.yaw_rad;
    const added_speed = mtx.Vector.init(0, move_accel, 0).rotateZ(target_direction);

    // Add to current speed
    this.body.speed = this.body.speed.add4(added_speed);

    // Cap speed
    const speed_var = this.body.speed.length2();
    if (speed_var > max_speed) {
        const speed_direction = this.body.speed.normalize2();
        this.body.speed = speed_direction.mulScalar2(max_speed);
    }

    // Apply gravity, and also jump
    this.body.speed.v[2] -= collision.gravity;
    if (js.input.keys[' '].isHeld() and this.body.speed.v[2] <= 0 and collision.isOnFloor(&this.body.shape)) {
        this.body.speed.v[2] = 3;
        }

    this.body.moveAndCollide();

    // Move camera
    const camera_distance_h = 50;
    const camera_distance_v = 10;
    render.camera.position = this.body.position.add4(
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
        .pos = .{ this.body.position.v[0], this.body.position.v[1], this.body.position.v[2] },
        .rot = .{ 0, 0, render.camera.yaw_rad },
        .origin = .{ 0.5, 0 },
    }));
}
