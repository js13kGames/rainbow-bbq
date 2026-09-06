const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const render = @import("render.zig");
const mtx = @import("mtx.zig");
const camera = @import("camera.zig");
const gbcompress = @import("build/gbcompress.zig");
const Player = @import("Player.zig");
const Enemy = @import("Enemy.zig");
const collision = @import("collision.zig");

pub const std_options = std.Options{
    .logFn = struct {
        fn inner(
            comptime message_level: std.log.Level,
            comptime scope: @EnumLiteral(),
            comptime format: []const u8,
            args: anytype,
        ) void {
            var buf: [2048]u8 = undefined;
            const str = std.fmt.bufPrint(&buf, format, args) catch "could not format string";
            js.log(message_level, str);
            _ = scope;
        }
    }.inner,
};

/// This is the "initial" function
export fn a() void {
    // Upload dummy texture
    const texture_data = js.staticAlloc(u8, Sprite.atlas_width * Sprite.atlas_height);
    render.matrix_stack.appendAssumeCapacity(.{});

    const compressed = @embedFile("atlas.bin");
    gbcompress.decompress(compressed, texture_data) catch unreachable;
    js.uploadTexture(texture_data, Sprite.atlas_width, Sprite.atlas_height);

    Player.player.init(.init(0, 0, 1));
    collision.initWorld();

    Enemy.initAll();
    _ = Enemy.spawn(.init(100, 100, 0), .red);
}

var frame: f32 = 0;

/// This is the main entrypoint
export fn b() void {
    frame += 1.0 / 60.0;
    js.input.update();

    Player.player.update();

    // Render main game world
    {
        const matrix = render.camera.getMatrix();
        render.pushMatrix(&matrix);
        defer render.popMatrix();

        // Draw floor
        render.drawQuad(Sprite.floor.spr, .fromAtlas(Sprite.floor, .{
            .scale = .{ 16, 16 },
            .rot = .{ -std.math.pi / 2.0, 0, 0 },
        }));

        Player.player.draw();

        for (&collision.world_walls) |*wall| {
            render.drawPolygon3D(wall);
        }

        for (&Enemy.enemies) |*enemy| {
            enemy.update();
            enemy.draw();
        }

        render.flush();
    }

    // Render UI
    {
        // Create 2D camera matrix
        const camera_matrix = comptime (camera.Camera2D{
            .x = 80,
            .y = -72,
            .width = 160,
            .height = 144,
            .z_near = -10,
            .z_far = 10,
        }).getMatrix();
        render.pushMatrix(&camera_matrix);
        defer render.popMatrix();

        // Ok now draw a sprite
        const horn_sprite = Sprite.horn;
        render.drawQuad(horn_sprite.spr, .fromAtlas(horn_sprite, .{
            .pos = .{ 12, 105, 0 },
            .rot = .{ std.math.pi / 2.0, 0, 0 },
        }));

        render.flush();
    }
}
