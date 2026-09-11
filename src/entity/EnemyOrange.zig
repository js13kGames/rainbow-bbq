const EnemyGreen = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [8]mtx.Vec2 = undefined,
wander_dir: f32 = 0,
wander_time: u32 = 0,
hidden: bool = false,
hidden_time: u32 = 0,

const speed_accel: f32 = 0.002;
const speed_max: f32 = 0.5;
const hide_distance: f32 = 140;
const max_hide_time: u32 = 60 * 5;

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

    const player_distance = entity.distanceTo(Entity.Player.player);
    const player_direction = entity.directionTo(Entity.Player.player);

    if (this.hidden) {
        this.wander_time += 1;
        entity.body.speed.v[0] = 0;
        entity.body.speed.v[1] = 0;
        this.hidden_time += 1;
        if (this.hidden_time == max_hide_time or player_distance > hide_distance) {
            entity.flags.hurt_player = .regular;
            this.hidden = false;
            this.wander_time = 0;
        }
    } else {
        if (this.hidden_time != 0) this.hidden_time -= 1;
        if (this.wander_time == 0) {
            this.wander_time = (60 * 4) + js.irandom(60 * 4);

            const dir = js.frandom(1);
            this.wander_dir = player_direction + (dir * dir * std.math.tau * std.math.sign(dir - 0.5));
        }
        this.wander_time -= 1;

        entity.moveTowards(this.wander_dir, speed_accel, speed_max, 0);

        // Hide if near the player
        if (this.hidden_time == 0 and player_distance < hide_distance) {
            this.hidden = true;
            entity.flags.hurt_player = .always;
        }
    }

    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_orange;

    const frame: usize = @intFromBool(this.hidden);
    const siner = js.sin(@as(f32, @floatFromInt(this.wander_time)) / 20.0) / 7.0;

    const xscale: f32 = if (this.hidden) 1 else 1 + siner;
    const angle: f32 = if (this.hidden) siner else 0;

    render.drawSpriteBillboard(Sprite.enemy_orange, .{
        .frame = frame,
        .pos = entity.body.position,
        .scale = .{ xscale, 1 },
        .angle = angle,
    });
}
