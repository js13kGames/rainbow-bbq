const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const render = @import("render.zig");
const mtx = @import("mtx.zig");
const camera = @import("camera.zig");
const gbcompress = @import("build/gbcompress.zig");
const Entity = @import("Entity.zig");
const collision = @import("collision.zig");
const ui = @import("ui.zig");
const world = @import("world.zig");

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

pub fn panic(msg: []const u8, stack_stace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = stack_stace;
    _ = ret_addr;
    std.log.err("{s}", .{msg});

    {
        // Required here, to not trigger recursive panic calls, due to "unreachable code reached".
        @setRuntimeSafety(false);
        unreachable;
    }
}

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

    restart();
}

pub fn restart() void {
    Entity.initAll();
    world.init();
}

/// This is the main entrypoint
export fn b() void {
    js.input.update();

    // Render main game world
    for (&Entity.all) |*entity| entity.update();

    // Update done, now begin rendering
    {
        // Set camera matrix
        const matrix = render.camera.getMatrix();
        render.pushMatrix(&matrix);
        defer render.popMatrix();

        // Draw collision polygons
        for (&world.world_shapes) |*wall| render.drawPolygon3D(wall);

        // Render entities
        for (&Entity.all) |*entity| entity.draw();

        // World pass done
        render.flush();
    }

    // Render UI
    ui.run();
}
