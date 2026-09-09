const EnemyYellow = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [16]mtx.Vec2 = undefined,
time: usize,

const radius: f32 = 120;
const ring_thickness: f32 = 8;

pub fn init(entity: *Entity, pos: mtx.Vector, timer: usize) void {
    entity.inner = .{ .attack_yellow = .{ .time = timer } };
    const this = &entity.inner.attack_yellow;

    entity.flags = .{ .alive = true, .hurt_player = true };
    entity.body = .initCircle(pos, &this.points, 4, radius);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.attack_yellow;
    this.time -= 1;

    if (this.time == 0) {
        entity.flags.alive = false;
    }
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.attack_yellow;

    // Draw surrounding ring
    const time_offset: f32 = @as(f32, @floatFromInt(this.time)) / 100.0;
    const step = std.math.tau / @as(f32, @floatFromInt(this.points.len));
    for (0..this.points.len) |i| {
        const angle = step * @as(f32, @floatFromInt(i)) + time_offset;
        const verts = render.vertex_buffer.addManyAsSliceAssumeCapacity(6);

        // I messed up the vertex order, but it generates a cool pattern, so I'm keeping it
        verts[3] = buildRingVert(angle, radius, entity.body.position);
        verts[2] = buildRingVert(angle, radius - ring_thickness, entity.body.position);
        verts[1] = buildRingVert(angle + step, radius - ring_thickness, entity.body.position);
        verts[0] = buildRingVert(angle + step, radius, entity.body.position);
        verts[4] = verts[1];
        verts[5] = verts[2];
    }

    // Draw sparks
    if (this.time & 1 != 0) {
        for (0..3) |_| {
            const frame = @as(usize, @trunc(js.random() * 3.0));
            const angle = js.random() * std.math.tau;

            const sprite = Sprite.attack_yellow;
            render.drawQuad(sprite.spr.frame(frame), .fromAtlas(sprite, .{
                .size = .{ 50, radius - ring_thickness },
                .origin = .{ 0.5, 0 },
                .pos = .{ entity.body.position.v[0], entity.body.position.v[1], entity.body.position.v[2] + 1 },
                .rot = .{ -std.math.pi / 2.0, 0, angle },
            }));
        }
    }
}

fn buildRingVert(angle: f32, distance: f32, pos: mtx.Vector) render.Vertex {
    const spr = Sprite.white.spr;
    const color = Sprite.attack_yellow.colors.fore;
    return .{
        .pos = render.transformVector(pos.add4((mtx.Vector{ .v = .{ distance, 0, 1, 0 } }).rotateZ(angle))),
        .uv = .{ spr.u[0], spr.v[0] },
        .color_fore = color,
        .color_back = color,
    };
}
