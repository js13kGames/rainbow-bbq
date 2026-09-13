const EnemyGreen = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [8]mtx.Vec2 = undefined,
wandering: Entity.Wandering = .{},
hidden: bool = false,
hidden_time: u32 = 0,

const speed_accel: f32 = 0.002;
const speed_max: f32 = 0.5;
const hide_distance: f32 = 140;
const max_hide_time: u32 = 90;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_orange = .{} };
    const this = &entity.inner.enemy_orange;

    entity.flags = .{ .alive = true, .enemy_kind = .orange, .hurt_player = .regular };
    entity.body = .initCircle(pos, &this.points, 17, 11);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.enemy_orange;

    if (this.hidden) {
        const player_distance = entity.distanceTo(Entity.Player.player);

        entity.body.speed.v[0] = 0;
        entity.body.speed.v[1] = 0;
        this.hidden_time += 1;
        if (this.hidden_time == max_hide_time or player_distance > hide_distance) {
            entity.flags.hurt_player = .regular;
            this.hidden = false;
            this.wandering.wander_time = 0;
        }
    } else {
        const is_near = entity.wander(&this.wandering);

        // Hide if near the player
        if (is_near) {
            if (this.hidden_time == 0) {
                this.hidden = true;
                entity.flags.hurt_player = .always;
            }
        } else {
            this.hidden_time = 0;
        }
    }

    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_orange;

    const frame: usize = @intFromBool(this.hidden);
    const siner = js.sin(@as(f32, @floatFromInt(this.hidden_time)) / 20.0) / 7.0;

    const xscale: f32 = if (this.hidden) 1 else 1 + siner;
    const angle: f32 = if (this.hidden) siner else 0;

    render.drawSpriteBillboard(Sprite.enemy_orange, .{
        .frame = frame,
        .pos = entity.body.position,
        .scale = .{ xscale, 1 },
        .angle = angle,
    });
}
