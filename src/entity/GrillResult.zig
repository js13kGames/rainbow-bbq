const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

content: [6]Entity.EnemyKind,
time: usize = 0,
prev_applied: usize = 0,

const interval_time: usize = 15;

pub fn init(entity: *Entity, content: [6]Entity.EnemyKind) void {
    entity.inner = .{ .grill_result = .{ .content = content } };
    entity.flags = .{ .alive = true };

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.grill_result;
    this.time += 1;

    _, const eaten = this.getSpearAndEaten();
    const num_eaten: usize = @popCount(eaten.bits.mask);
    if (num_eaten != this.prev_applied) {
        this.prev_applied = num_eaten;

        const player = &Entity.Player.player.inner.player;
        player.score_multiply *= 2;
        player.score_multiply_timer = 660;
    }

    if (this.time >= 40 + interval_time * 6 + 60) {
        entity.flags.alive = false;
    }
}

pub fn draw(entity: *const Entity) void {
    _ = entity;
}

const draw_x: f32 = 80;
const draw_y: f32 = 127;

pub fn drawGUI(this: *const @This()) void {
    const content, const eaten = this.getSpearAndEaten();

    // Draw the rainbow
    for (0..6) |i| {
        const enemy: Entity.EnemyKind = @enumFromInt(i);

        var color = Entity.Grill.sprite_map.get(enemy).color;
        if (!eaten.contains(enemy)) {
            color &= 0x3FFF_FFFF;
        }

        // Draw rainbow slice
        const i_f = @as(f32, @floatFromInt(i)) / 5.0;
        const scale = 1 + i_f + i_f * i_f * 0.3;
        const sprite = Sprite.rainbow;
        render.drawQuad(sprite.spr, .{
            .pos = .{ draw_x, draw_y, 0 },
            .size = .{ 32 * scale, 20 * scale },
            .color_back = 0,
            .color_fore = color,
            .origin = .{ 0.5, 0 },
            .rot = .{ std.math.pi / 2.0, 0, 0 },
        });
    }

    // Draw the spear
    Entity.Grill.drawSpear(
        .init(draw_x, draw_y + 5, 0),
        .{ std.math.pi / 2.0, std.math.pi / 2.0, 0 },
        content,
        std.math.pi / 3.0,
    );
}

fn getSpearAndEaten(this: *const @This()) struct { []const Entity.EnemyKind, std.EnumSet(Entity.EnemyKind) } {
    const progress: usize = @min(6, if (this.time > 40) (this.time - 40) / interval_time else 0);

    const content: []const Entity.EnemyKind = this.content[0 .. 6 - progress];
    const eaten: []const Entity.EnemyKind = this.content[6 - progress ..];

    var eaten_color: std.EnumSet(Entity.EnemyKind) = .empty;
    for (eaten) |enemy| {
        eaten_color.setPresent(enemy, true);
    }

    return .{ content, eaten_color };
}
