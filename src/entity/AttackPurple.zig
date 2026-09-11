const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [8]mtx.Vec2 = undefined,
time: usize = 0,

pub fn init(entity: *Entity, pos: mtx.Vector, direction: f32) void {
    entity.inner = .{ .attack_purple = .{} };
    const this = &entity.inner.attack_purple;

    entity.flags = .{ .alive = true, .hurt_player = .always };
    entity.body = .initCircle(pos, &this.points, 16, 3);
    entity.body.speed = mtx.Vector.init(2, 0, 0).rotateZ(direction);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.attack_purple;

    entity.body.moveAndCollide();

    if (entity.body.collided or this.time > 300) {
        entity.flags.alive = false;
    }
}

pub fn draw(entity: *const Entity) void {
    render.drawSpriteBillboard(Sprite.attack_purple, .{
        .pos = entity.body.position.add4(.init(
            js.frandom(2) - 1,
            js.frandom(2) - 1,
            6 + js.frandom(2) - 1,
        )),
    });
}
