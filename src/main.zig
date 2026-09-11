const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const render = @import("render.zig");
const mtx = @import("mtx.zig");
const camera = @import("camera.zig");
const gbcompress = @import("build/gbcompress.zig");
const Entity = @import("Entity.zig");
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
    // Ensure there is always a unit matrix at the bottom of the stack
    render.matrix_stack.appendAssumeCapacity(.{});
    Sprite.init();

    // Decompress and upload texture
    const texture_data = js.staticAlloc(u8, Sprite.atlas_width * Sprite.atlas_height);
    const compressed = @embedFile("atlas.bin");
    gbcompress.decompress(compressed, texture_data) catch unreachable;
    js.uploadTexture(texture_data, Sprite.atlas_width, Sprite.atlas_height);

    collision.initWorld();

    Entity.initAll();
    Entity.Player.init(Entity.findFree().?, .init(0, 0, 1));
    Entity.Grill.init(Entity.findFree().?, .init(0, 0, 1));

    Entity.EnemyRed.init(Entity.findFree().?, .init(100, 100, 0));
    Entity.EnemyYellow.init(Entity.findFree().?, .init(0, -500, 0));
    Entity.EnemyGreen.init(Entity.findFree().?, .init(0, 500, 0));
    Entity.EnemyOrange.init(Entity.findFree().?, .init(200, 0, 0));
    Entity.EnemyPurple.init(Entity.findFree().?, .init(-200, 0, 0));
    Entity.EnemyBlue.init(Entity.findFree().?, .init(-200, 0, 0));
}

var frame: f32 = 0;

/// This is the main entrypoint
export fn b() void {
    frame += 1.0 / 60.0;
    js.input.update();

    // Render main game world
    {
        for (&Entity.all) |*entity| entity.update();

        // Update done, now set camera matrix
        const matrix = render.camera.getMatrix();
        render.pushMatrix(&matrix);
        defer render.popMatrix();

        // Draw collision polygons
        for (&collision.world_walls) |*wall| {
            render.drawPolygon3D(wall);
        }

        // Render entities
        for (&Entity.all) |*entity| entity.draw();

        // World pass done
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
        const player = &Entity.Player.player.inner.player;
        const content: []const Entity.EnemyKind = player.speared[0..player.num_speared];
        Entity.Grill.drawSpear(
            .init(12, 105, 0),
            .{ std.math.pi / 2.0, 0, 0 },
            content,
        );

        render.flush();
    }
}
