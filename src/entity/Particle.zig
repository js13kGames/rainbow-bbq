const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

time: usize,
color: u32,
w: f32,

pos: mtx.Vector,
speed: mtx.Vector = .zero,

pub fn init(entity: *Entity, this: @This()) void {
    entity.inner = .{ .particle = this };
    entity.flags = .{ .alive = true };

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.particle;

    this.pos = this.pos.add4(this.speed);

    if (this.time == 0) {
        entity.flags.alive = false;
        return;
    }
    this.time -= 1;
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.particle;

    render.drawQuad(Sprite.smoke.spr, .{
        .pos = this.pos.v,
        .size = .{ this.w, this.w },
        .color_back = this.color,
        .color_fore = render.buildColor(.{ 0, 0, 0, 255 }),
        .rot = .{ 0, 0, render.camera.yaw_rad, 0 },
    });
}

pub fn spawnEvaporate(pos: mtx.Vector, speed: f32, color: u32, w: f32) void {
    const particle = Entity.findFree() orelse return;

    Entity.Particle.init(particle, .{
        .w = w,
        .time = js.irandom(25) + 5,
        .pos = pos,
        .color = color,
        .speed = .init(
            js.frandom(speed * 2) - speed,
            js.frandom(speed * 2) - speed,
            js.frandom(speed * 2) - speed,
        ),
    });
}
