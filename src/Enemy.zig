const Enemy = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const mtx = @import("mtx.zig");
const render = @import("render.zig");
const collision = @import("collision.zig");

body: collision.PhysicsEntity,
points: [8]mtx.Vec2 = undefined,
alive: bool = false,
kind: Kind,

pub var enemies: [256]Enemy = undefined;

pub fn initAll() void {
    for (&enemies) |*enemy| {
        enemy.alive = false;
        enemy.body.shape.points = &enemy.points;
    }
}

/// Spawns a new enemy
pub fn spawn(pos: mtx.Vector, kind: KindTag) ?*Enemy {
    // Find enemy slot to occupy
    const enemy = blk: {
        for (&enemies) |*enemy| {
            if (!enemy.alive) break :blk enemy;
        }
        return null;
    };

    // Set properties
    enemy.alive = true;
    enemy.body.position = pos;

    switch (kind) {
        .red => enemy.kind = .{ .red = .{} },
    }

    // Update shape
    enemy.body.shape.buildCircle(pos.v[0], pos.v[1], pos.v[2], 8, 8);

    return enemy;
}

pub fn update(this: *Enemy) void {
    if (!this.alive) return;

    this.kind.update();

    // Now do physics
    this.body.moveAndCollide();
}

pub fn draw(this: *const Enemy) void {
    if (!this.alive) return;

    this.kind.draw();

    // render.drawPolygon3D(&this.body.shape);
}

pub const KindTag = enum(u8) {
    red,
};

pub const Kind = union(KindTag) {
    red: @import("enemy/Red.zig"),

    pub fn update(this: *Kind) void {
        switch (this.*) {
            .red => |*kind| kind.update(),
        }
    }

    pub fn draw(this: *const Kind) void {
        switch (this.*) {
            .red => |*kind| kind.draw(),
        }
    }
};
