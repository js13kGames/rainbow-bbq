const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");
const collision = @import("../collision.zig");

points: [8]mtx.Vec2 = undefined,
time: usize = 0,

const height = 22;
const radius = 6;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_purple = .{} };
    const this = &entity.inner.enemy_purple;

    entity.flags = .{ .alive = true, .enemy_kind = .purple };
    entity.body = .initCircle(pos, &this.points, height, radius);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.enemy_purple;

    this.time += 1;

    // Shoot projectile
    if (this.time == 60 * 3) {
        std.log.info("shoot projectile", .{});
    }

    // Teleport out of frame
    if (this.time == 60 * 6) {
        // Spawn particles
        std.log.info("spawn particles", .{});

        entity.body = .initCircle(.init(0, 0, -1000), &this.points, height, radius);
    }

    // Move back INTO frame
    if (this.time == 70 * 7) {
        const player_position = Entity.Player.player.body.position;

        for (0..50) |_| {
            this.time = 0;

            const direction = js.frandom(std.math.tau);
            const distance = js.frandom(100) + 150;
            const new_pos = mtx.Vector.init(distance, 0, 0).rotateZ(direction).add2(player_position);

            // TODO: validate world bounds

            entity.body = .initCircle(new_pos, &this.points, height, radius);

            // Move upwards
            const col = collision.collideWithWorld(&entity.body.shape) orelse break;
            const height_diff = @abs(player_position.v[0] - col.floor);
            entity.body.shape.move(.init(0, 0, col.floor));

            if (height_diff < 150) break;
        }

        // Spawn particles
        std.log.info("spawn particles", .{});
    }
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_purple;

    var frame: usize = 0;
    var yscale: f32 = 1;
    var origin_x: f32 = 0.5;

    if (this.time >= 60 * 2 and this.time < 60 * 4) {
        frame = 1;

        if (this.time <= 60 * 3) {
            const shake = (this.time >> 2) & 1;
            origin_x = 0.5 + @as(f32, if (shake == 0) 0.08 else -0.08);
        }
    } else {
        yscale = js.sin(@as(f32, @floatFromInt(this.time)) / 17.0) * 0.1 + 1;
    }

    render.drawSpriteBillboard(Sprite.enemy_purple, .{
        .frame = frame,
        .pos = entity.body.position,
        .scale = .{ 1, yscale },
        .origin = .{ origin_x, 0 },
    });
}
