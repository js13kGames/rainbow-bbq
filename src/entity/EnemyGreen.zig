const EnemyGreen = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");

points: [8]mtx.Vec2 = undefined,
time: usize = 0,

const speed_accel: f32 = 0.03;
const speed_max: f32 = 2.0;
const gawk_distance: f32 = 70;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_green = .{} };
    const this = &entity.inner.enemy_green;

    entity.flags = .{ .alive = true, .enemy_kind = .green };
    entity.body = .initCircle(pos, &this.points, 13, 6);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.enemy_green;

    const target_direction = entity.directionTo(Entity.Player.player);
    const target_distance = entity.distanceTo(Entity.Player.player);

    if (target_distance < gawk_distance) {
        // Gawkin'
        entity.body.speed = entity.body.speed.mulScalar2(0.93);
    } else {
        this.time +%= 1;

        entity.moveTowards(target_direction, speed_accel, speed_max, 2.6);
    }

    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_green;

    var frame: usize = 0;

    const target_distance = entity.distanceTo(Entity.Player.player);
    if (target_distance >= gawk_distance) {
        frame = 1 + ((this.time >> 3) & 1);
    }

    render.drawSpriteBillboard(Sprite.enemy_green, .{
        .frame = frame,
        .pos = entity.body.position,
        .scale = .{ if ((this.time >> 4) & 1 != 0) 1 else -1, 1 },
    });
}
