const Player = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const render = @import("render.zig");
const mtx = @import("mtx.zig");
const js = @import("js.zig");
const collision = @import("collision.zig");

position: mtx.Vector,
speed: mtx.Vector,

points: [8]mtx.Vec2 = undefined,
shape: collision.Polygon = undefined,

const move_accel: f32 = 0.035;
const max_speed = 1.5;

const player_width = 7;
const player_height = 16;

pub fn init(this: *Player, pos: mtx.Vector) void {
    this.position = pos;
    this.speed = .init(0, 0, 0);
    this.shape.points = &this.points;
    this.shape.buildCircle(pos.v[0], pos.v[1], pos.v[2], player_height, player_width);
}

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
        this.shape.move(this.speed);

        while (collision.collideWithWorld(&this.shape)) |eject| {
            this.shape.move(.init(
                eject.pen_dir[0] * (eject.pen_length + 0.001),
                eject.pen_dir[1] * (eject.pen_length + 0.001),
                0,
            ));

            const angle = js.atan2(eject.pen_dir[0], eject.pen_dir[1]);
            var rot = this.speed.rotateZ(angle);
            rot.v[1] = 0;
            this.speed = rot.rotateZ(-angle);
        }

        this.position.v[0] = this.shape.middle[0];
        this.position.v[1] = this.shape.middle[1];
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
        .origin = .{ 0.5, 0 },
    }));
}
