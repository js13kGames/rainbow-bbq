const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const render = @import("render.zig");
const mtx = @import("mtx.zig");
const camera = @import("camera.zig");
const Entity = @import("Entity.zig");

var gameover_time: usize = 0;

pub fn run() void {
    const player = &Entity.Player.player.inner.player;

    // Create 2D camera matrix
    const camera_matrix = comptime (camera.Camera2D{
        .x = 80,
        .y = -72,
        .width = 160,
        .height = 144,
        .z_near = -1000,
        .z_far = 1000,
    }).getMatrix();
    render.pushMatrix(&camera_matrix);
    defer render.popMatrix();

    // "The player is dead"
    if (player.dead) drawGameover(player) else drawGameplay(player);

    render.flush();
}

fn drawGameplay(player: *const Entity.Player) void {
    // Ok now draw the horn
    const content: []const Entity.EnemyKind = player.speared[0..player.num_speared];
    Entity.Grill.drawSpear(
        .init(12, 105, 0),
        .{ std.math.pi / 2.0, 0, 0 },
        content,
        std.math.pi / 3.0,
    );

    // Excellent! Should we also draw score?
    render.drawText("SCORE", .{});
    render.drawNumber(player.score, .{
        .pos = .init(8 * 6, 0, 0),
        .scale = 1 + @as(f32, @floatFromInt(player.score_gain)) / 15.0,
    });

    render.drawText("X", .{
        .pos = .init(0, 8, 0),
    });
    render.drawNumber(player.score_multiply, .{
        .pos = .init(8, 8, 0),
        .scale = 1 + @as(f32, @floatFromInt(player.score_multiply_timer)) / 300.0,
    });

    // This is crazy, but what if we also draw HP?
    render.drawText("HP", .{ .pos = .init(160 - 8 * 4, 0, 0) });
    render.drawNumber(player.hp, .{ .pos = .init(160 - 8, 0, 0) });

    // Draw grill results
    for (&Entity.all) |*entity| {
        if (entity.flags.alive) switch (entity.inner) {
            .grill_result => |*grill_result| grill_result.drawGUI(),
            else => {},
        };
    }

    // Draw charge bar
    render.drawQuad(Sprite.arrow.spr, .{
        .size = .{ 7, 55 * player.charge },
        .origin = .{ 0, 0 },
        .pos = .{ 147, 132, 0, 0 },
        .color_back = 0xFFFF_FFFF,
        .color_fore = 0xFFFF_FFFF,
        .rot = .{ std.math.pi / 2.0, 0, 0, 0 },
    });
}

fn drawGameover(player: *const Entity.Player) void {
    const highscore = js.updateHighscore(player.score);

    render.drawText("GAME OVER", .{
        .centered = true,
        .pos = .init(80, 20, 0),
        .scale = 2,
    });

    render.drawText("SCORE", .{
        .centered = true,
        .pos = .init(80, 40, 0),
    });

    render.drawNumber(player.score, .{
        .centered = true,
        .pos = .init(80, 48, 0),
    });

    render.drawText("HIGHSCORE", .{
        .centered = true,
        .pos = .init(80, 60, 0),
    });

    render.drawNumber(highscore, .{
        .centered = true,
        .pos = .init(80, 68, 0),
    });

    gameover_time += 1;
    if (gameover_time > 150) {
        render.drawText("JUMP TO RESTART", .{
            .centered = true,
            .pos = .init(80, 100, 0),
        });

        if (js.input.keys[' '].isPressed()) {
            gameover_time = 0;
            @import("root").restart();
        }
    }
}
