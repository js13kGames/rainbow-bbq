const std = @import("std");
const js = @import("js.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const Camera = @import("camera.zig").Camera2D;
const gbcompress = @import("build/gbcompress.zig");

const Sprite = @import("Sprite");

/// This is the "initial" function
export fn a() void {
    const camera = Camera{
        .x = 0,
        .y = 0,
        .width = 160,
        .height = 144,
        .z_near = -10,
        .z_far = 1000,
    };
    const matrix = camera.getMatrix();
    render.pushMatrix(&matrix);

    // Upload dummy texture
    const texture_data = js.staticAlloc(u8, Sprite.atlas_width * Sprite.atlas_height);

    const compressed = @embedFile("atlas.bin");
    gbcompress.decompress(compressed, texture_data) catch unreachable;
    js.uploadTexture(texture_data, Sprite.atlas_width, Sprite.atlas_height);
}

var frame: f32 = 0;

/// This is the main entrypoint
export fn b() void {
    frame += 1.0 / 60.0;
    js.input.update();

    const sprite = render.Sprite.fromAtlas(Sprite.simple, 0.5, 0.5);

    const transform = render.Sprite.Transform{
        .color_back = Sprite.simple.colors.back,
        .color_fore = Sprite.simple.colors.fore,
        .pos = .{ 30, 30 },
        .angle = frame,
        .scale = .{ 4, 4 },
    };

    sprite.draw(&transform);

    const mtx = transform.toMatrix();
    render.pushMatrix(&mtx);
    defer render.popMatrix();

    sprite.draw(&.{
        .color_back = Sprite.simple.colors.back,
        .color_fore = Sprite.simple.colors.fore,
        .scale = .{ 0.5, 0.5 },
        .pos = .{ -20, -20 },
    });

    render.flush();
}
