const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

difficulty: f32 = 0.00002,
spawn_probability: f32 = 0.2,

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .spawner = .{} };
    entity.flags = .{ .alive = true };
    entity.body.position = pos;

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

    this.difficulty = @min(this.difficulty + 0.00001, 0.001);
    this.spawn_probability += this.difficulty;

    const chance = js.frandom(1) + 0.2;
    if (chance < this.spawn_probability) {
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
