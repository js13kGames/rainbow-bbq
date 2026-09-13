const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [16]mtx.Vec2 = undefined,
time: usize,

pub fn init(entity: *Entity, pos: mtx.Vector, timer: usize, radius: f32, height: f32) void {
    entity.inner = .{ .hitbox = .{ .time = timer } };
    const this = &entity.inner.hitbox;

    entity.flags = .{ .alive = true, .hurt_player = .always };
    entity.body = .initCircle(pos, &this.points, height, radius);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.hitbox;

    if (this.time == 0) {
        entity.flags.alive = false;
    } else {
        this.time -= 1;
    }
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.hitbox;
    _ = this;
}

pub fn drawRing(time: usize, num_points: usize, pos: mtx.Vector, radius: f32, ring_thickness: f32, color: u32) void {
    // Draw surrounding ring
    const time_offset: f32 = @as(f32, @floatFromInt(time)) / 100.0;
    const step = std.math.tau / @as(f32, @floatFromInt(num_points));
    for (0..num_points) |i| {
        const angle = step * @as(f32, @floatFromInt(i)) + time_offset;
        const verts = render.vertex_buffer.addManyAsSliceAssumeCapacity(6);

        // I messed up the vertex order, but it generates a cool pattern, so I'm keeping it
        verts[0] = buildRingVert(angle + step, radius, pos, color);
        verts[1] = buildRingVert(angle + step, radius - ring_thickness, pos, color);
        verts[2] = buildRingVert(angle, radius - ring_thickness, pos, color);
        verts[3] = buildRingVert(angle, radius, pos, color);
        verts[4] = verts[1];
        verts[5] = verts[2];
    }
}

fn buildRingVert(angle: f32, distance: f32, pos: mtx.Vector, color: u32) render.Vertex {
    const spr = Sprite.arrow.spr;
    return .{
        .pos = render.transformVector(pos.add4((mtx.Vector{ .v = .{ distance, 0, 1, 0 } }).rotateZ(angle))),
        .uv = .{ spr.u[0], spr.v[0] },
        .color_fore = color,
        .color_back = color,
    };
}
