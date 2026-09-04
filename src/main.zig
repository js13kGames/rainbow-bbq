const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const render = @import("render.zig");
const math = @import("math.zig");
const Camera = @import("camera.zig").CameraPerspective;
const gbcompress = @import("build/gbcompress.zig");

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

    const sprite = Sprite.simple;
    var transform = render.SpriteDescriptor.fromAtlas(Sprite.simple, .{
        .origin = .{ 0.5, 0.5 },
        .pos = .{ 30, 30 },
        .angle = frame,
        .scale = .{ 4, 4 },
    });

    var move: math.Vector = .{ .v = .{ 0, 0, 0, 1 } };

    const move_speed = 0.5;
    if (js.input.keys['A'].isHeld()) move.v[0] = -move_speed;
    if (js.input.keys['D'].isHeld()) move.v[0] = move_speed;
    if (js.input.keys['S'].isHeld()) move.v[1] = -move_speed;
    if (js.input.keys['W'].isHeld()) move.v[1] = move_speed;
    if (js.input.keys[16].isHeld()) move.v[2] = -move_speed;
    if (js.input.keys[' '].isHeld()) move.v[2] = move_speed;

    render.camera.position = render.camera.position.add3(move.rotateZ(render.camera.yaw_rad));

    const matrix = render.camera.getMatrix();
    render.pushMatrix(&matrix);
    defer render.popMatrix();

    // Draw text cube
    render.drawCube(sprite.spr);

    // Draw test billboard
    render.drawBillboard(sprite.spr, .{
        .size = .{ 16 + js.sin(frame) * 2, 16 },
        .pos = .{ 0, 0, 0 },
    });

    render.drawBillboard(sprite.spr, .{
        .size = .{ 16, 16 },
        .pos = .{ 32, 0, 0 },
        .angle = frame,
    });

    // Draw BEEG sprite
    render.drawSprite(sprite.spr, transform);

    render.pushMatrix(&math.Matrix.from2DParams(30, 30, 4, 4, frame));
    defer render.popMatrix();

    // Draw orbiting sprite
    render.drawSprite(sprite.spr, transform.base(.{
        .size = .{ 8, 8 },
        .pos = .{ -20, -20 },
    }));

    render.flush();
}
