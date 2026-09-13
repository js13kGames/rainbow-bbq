const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");

time: usize,
color: u32,
w: f32,

pos: mtx.Vector,
speed: mtx.Vector = .zero,
speed_damp: mtx.Vector = .init(1, 1, 1),

scale: f32 = 1,
scale_delta: f32 = 0,

const speed_accel: f32 = 0.03;
const speed_max: f32 = 2.0;
const gawk_distance: f32 = 70;

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

    this.speed = this.speed.mul4(this.speed_damp);
    this.pos = this.pos.add4(this.speed);
    this.scale += this.scale_delta;

    if (this.time == 0 or this.scale <= 0) {
        entity.flags.alive = false;
        return;
    }
    this.time -= 1;
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.particle;

    render.drawQuad(Sprite.smoke.spr, .{
        .pos = this.pos.v,
        .size = .{ this.w * this.scale, this.w * this.scale },
        .color_back = this.color,
        .color_fore = render.buildColor(.{ 0, 0, 0, 255 }),
        .rot = .{ 0, 0, render.camera.yaw_rad, 0 },
    });
}
