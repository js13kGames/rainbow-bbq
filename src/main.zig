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
        for (&world.world_shapes, 0..) |*wall, i| {
            render.drawPolygon3D(wall, &world.world_texture[i]);
        }

        // Render entities
        for (&Entity.all) |*entity| entity.draw();

        drawFence();

        // World pass done
        render.flush();
    }

    // Render UI
    ui.run();
}

const w: f32 = world.level_size;
const num_fences = @as(usize, @trunc(w)) / (Sprite.fence.w * 2) + 1;
const fence_w: f32 = (w) / @as(f32, @floatFromInt(num_fences));

fn drawFence() void {
    const spr = Sprite.fence.spr;
    const color = Sprite.fence.colors;

    for (0..4) |i| {
        var matrix = mtx.Matrix{};
        _ = matrix
            .translate(.{ w / 2.0, w / 2.0, 0, 0 })
            .rotateZ(@as(f32, @floatFromInt(i)) * std.math.pi / 2.0)
            .translate(.{ -w / 2.1, w / 2.1, 0, 0 });

        render.pushMatrix(&matrix);
        defer render.popMatrix();

        for (0..num_fences) |j| {
            const verts = render.vertex_buffer.addManyAsSliceAssumeCapacity(6);

            for (0..4) |k| {
                const xi = k % 2;
                const yi = k / 2;

                const x: f32 = @as(f32, @floatFromInt(xi + j)) * fence_w;
                const y: f32 = @as(f32, @floatFromInt(yi)) * Sprite.fence.h;

                verts[k] = .{
                    .pos = render.transformVector(mtx.Vector.init(x, 0, y)),
                    .uv = .{ spr.u[1 - xi], spr.v[1 - yi] },
                    .color_fore = color.fore,
                    .color_back = color.back,
                };
            }

            verts[4] = verts[2];
            verts[5] = verts[1];
        }
    }
}
