const std = @import("std");
const js = @import("js.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const Camera = @import("camera.zig").CameraPerspective;
const gbcompress = @import("build/gbcompress.zig");

const Sprite = @import("Sprite");

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
var camera = Camera{
    .position = .{ .v = .{ 0, -2, 0, 1 } },
    .z_near = 0.1,
    .z_far = 1000,
};

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

    var move: math.Vector = .{ .v = .{ 0, 0, 0, 1 } };

    if (js.input.keys['A'].isHeld()) move.v[0] = -0.1;
    if (js.input.keys['D'].isHeld()) move.v[0] = 0.1;
    if (js.input.keys['S'].isHeld()) move.v[1] = -0.1;
    if (js.input.keys['W'].isHeld()) move.v[1] = 0.1;
    if (js.input.keys[16].isHeld()) move.v[2] = -0.1;
    if (js.input.keys[' '].isHeld()) move.v[2] = 0.1;

    camera.yaw_rad = -js.input.mouse_x / 300.0;
    camera.pitch_rad = -@max(@min(js.input.mouse_y / 300.0, std.math.pi / 2.01), -std.math.pi / 2.01);

    camera.position = camera.position.add3(move.rotateZ(camera.yaw_rad));

    const matrix = camera.getMatrix();
    render.pushMatrix(&matrix);
    defer render.popMatrix();

    render.drawCube(&sprite);

    sprite.draw(&.{
        .color_back = .{ 255, 255, 255, 255 },
        .color_fore = .{ 0, 0, 0, 255 },
        .scale = .{ 0.5 / sprite.size[0], 0.5 / sprite.size[1] },
    });

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
