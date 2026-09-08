const Player = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");
const collision = @import("../collision.zig");

points: [8]mtx.Vec2 = undefined,

/// Singleton instance
pub var player: *Entity = undefined;

const move_accel: f32 = 0.035;
const max_speed = 1.6;

const player_width = 14;
const player_height = 16;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .player = .{} };
    const this = &entity.inner.player;

    entity.flags = .{ .alive = true };
    entity.body = .initCircle(pos, &this.points, player_height, player_width / 2.0);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };

    player = entity;
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.player;
    _ = this;

    // Prepare movement
    entity.moveTowards(render.camera.yaw_rad + std.math.pi / 2.0, move_accel, max_speed, 0);
    if (js.input.keys[' '].isHeld() and entity.body.speed.v[2] <= 0 and collision.isOnFloor(&entity.body.shape)) {
        entity.body.speed.v[2] = 3;
    }

    // And now go
    entity.body.moveAndCollide();

    // Move camera
    const camera_distance_h = 50;
    const camera_distance_v = 10;
    render.camera.position = entity.body.position.add4(
        mtx.Vector
            .init(0, -camera_distance_h, camera_distance_v)
            .rotateX(render.camera.pitch_rad)
            .rotateZ(render.camera.yaw_rad),
    );
    render.camera.position.v[3] = 1;
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.player;
    _ = this;

    // Render the thing
    const sprite = Sprite.unicorn;
    render.drawQuad(sprite.spr, .fromAtlas(sprite, .{
        .pos = .{ entity.body.position.v[0], entity.body.position.v[1], entity.body.position.v[2] },
        .rot = .{ 0, 0, render.camera.yaw_rad },
        .origin = .{ 0.5, 0 },
    }));
}
