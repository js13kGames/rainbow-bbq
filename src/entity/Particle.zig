const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");

time: usize,
sprite: *const Sprite,
colors: Sprite.Colors,
w: usize,
h: usize,

pos: mtx.Vector,
speed: mtx.Vector = .init(0, 0, 0),
speed_delta: mtx.Vector = .init(0, 0, 0),

angle: f32 = 0,
angle_delta: f32 = 0,

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

    if (this.time == 0) {
        entity.flags.alive = false;
        return;
    }
    this.time -= 1;

    this.speed = this.speed.add4(this.speed_delta);
    this.pos = this.pos.add4(this.speed);
    this.angle += this.angle_delta;
    this.scale += this.scale_delta;
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.particle;

    render.drawQuad(this.sprite, .{
        .pos = .{ this.pos.v[0], this.pos.v[1], this.pos.v[2] },
        .size = .{ @as(f32, @floatFromInt(this.w)) * this.scale, @as(f32, @floatFromInt(this.h)) * this.scale },
        .color_back = this.colors.back,
        .color_fore = this.colors.fore,
        .rot = .{ 0, this.angle, render.camera.yaw_rad },
    });
}
