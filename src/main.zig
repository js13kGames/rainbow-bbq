const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const camera = @import("camera.zig");
const gbcompress = @import("build/gbcompress.zig");
const Player = @import("Player.zig");

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
}

var frame: f32 = 0;
var player: Player = .{};

/// This is the main entrypoint
export fn b() void {
    frame += 1.0 / 60.0;
    js.input.update();

    const sprite = Sprite.simple;
    var transform = render.QuadDescriptor.fromAtlas(Sprite.simple, .{
        .origin = .{ 0.5, 0.5 },
        .pos = .{ 30, 30, 1 },
        .rot = .{ std.math.pi / 2.0, 0, frame },
        .scale = .{ 4, 4 },
    });

    player.update();

    // Render main game world
    {
        const matrix = render.camera.getMatrix();
        render.pushMatrix(&matrix);
        defer render.popMatrix();

        // Draw floor
        render.drawQuad(Sprite.floor.spr, .fromAtlas(Sprite.floor, .{
            .scale = .{ 10, 10 },
            .rot = .{ -std.math.pi / 2.0, 0, 0 },
        }));

        player.draw();

        // Draw test billboard
        render.drawQuad(sprite.spr, .{
            .size = .{ 16 + js.sin(frame) * 2, 16 },
            .pos = .{ 0, 0, 0 },
        });

        render.drawQuad(sprite.spr, .{
            .size = .{ 16, 16 },
            .pos = .{ 32, 0, 0 },
            .rot = .{ 0, frame, 0 },
        });

        // Draw BEEG sprite
        render.drawQuad(sprite.spr, transform);

        render.pushMatrix(&math.Matrix.from2DParams(30, 30, 4, 4, frame));
        defer render.popMatrix();

        // Draw orbiting sprite
        render.drawQuad(sprite.spr, transform.base(.{
            .size = .{ 8, 8 },
            .pos = .{ -20, -20, 0 },
            .rot = .{ std.math.pi / 2.0, 0, 0 },
        }));

        render.flush();
    }

    // Render UI
    {
        // Create 2D camera matrix
        const mtx = comptime (camera.Camera2D{
            .x = 80,
            .y = -72,
            .width = 160,
            .height = 144,
            .z_near = -10,
            .z_far = 10,
        }).getMatrix();
        render.pushMatrix(&mtx);
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
