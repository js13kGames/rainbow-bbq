const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

difficulty: f32 = 0.00002,
spawn_probability: f32 = 0.2,

pub var num_enemies: usize = 0;
const num_enemies_max = 200;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .spawner = .{} };
    entity.flags = .{ .alive = true };
    entity.body.position = pos;

    num_enemies = 0;

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

const spawner_table = [_]*const fn (entity: *Entity, pos: mtx.Vector) void{
    Entity.EnemyRed.init,
    Entity.EnemyOrange.init,
    Entity.EnemyYellow.init,
    Entity.EnemyGreen.init,
    Entity.EnemyBlue.init,
    Entity.EnemyPurple.init,
};

pub fn update(entity: *Entity) void {
    const this = &entity.inner.spawner;

    const player = &Entity.Player.player.inner.player;

    this.difficulty = @min(this.difficulty + 0.000005, 0.001);
    this.spawn_probability += this.difficulty;

    const chance = js.frandom(1) + 0.2;
    if (chance < this.spawn_probability and num_enemies < num_enemies_max and !player.dead) {
        num_enemies += 1;
        this.spawn_probability = 0;

        if (Entity.findFree()) |enemy| {
            const enemy_idx = js.irandom(spawner_table.len);
            spawner_table[enemy_idx](enemy, entity.body.position);
        }
    }
}

pub fn draw(entity: *const Entity) void {
    _ = entity;
}
