const EnemyYellow = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

const State = enum {
    approach,
    charge,
    launch,
    plugged,
};

points: [8]mtx.Vec2 = undefined,
time: usize = 0,
state: State = .approach,

const attack_time = 120;
const stuck_time = 70;
const attack_radius: f32 = 80;
const attack_ring_thickness: f32 = 8;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_yellow = .{} };
    const this = &entity.inner.enemy_yellow;

    entity.flags = .{ .alive = true, .enemy_kind = .yellow, .hurt_player = .regular };
    entity.body = .initCircle(pos, &this.points, 24, 12);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

const speed_accel: f32 = 0.02;
const speed_max: f32 = 0.7;

pub fn update(entity: *Entity) void {
    const this = &entity.inner.enemy_yellow;

    this.time += 1;

    switch (this.state) {
        .approach => {
            // That's the direction we want to go
            const target_direction = entity.directionTo(Entity.Player.player);
            entity.moveTowards(target_direction, speed_accel, speed_max, 2.6);

            // Are we close yet? Initiate attack?
            if (entity.distanceTo(Entity.Player.player) < 80 and entity.body.isGrounded()) {
                this.state = .charge;
                this.time = 0;
            }
        },

        .charge => {
            entity.body.speed = entity.body.speed.mulScalar2(0.6);
            if (this.time > 40) {
                this.state = .launch;
                entity.body.speed = .init(0, 0, 5);
            }
        },

        .launch => {
            if (entity.body.isGrounded()) {
                this.state = .plugged;
                entity.flags.hurt_player = .always;
                if (Entity.findFree()) |slot| {
                    Entity.Hitbox.init(slot, entity.body.position, attack_time, attack_radius, 4);
                    this.time = 0;
                }
            }
        },

        .plugged => {
            if (this.time >= attack_time) {
                entity.flags.hurt_player = .regular;
            }

            if (this.time == attack_time + stuck_time) {
                this.state = .approach;
                entity.body.speed = .init(0, 0, 2);
            }
        },
    }

    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_yellow;

    var angle: f32 = 0;
    var frame: usize = 0;
    var yscale: f32 = 1;
    angle = 0;

    switch (this.state) {
        .approach => {
            frame = 0;
            if ((this.time >> 4) & 1 == 1) {
                frame += 1;
                if ((this.time >> 5) & 1 == 1) frame += 1;
            }
        },

        .charge => {
            frame = 3;
            yscale = 1.0 - @as(f32, @floatFromInt(this.time)) / 90.0;
        },

        .launch, .plugged => {
            frame = 3;
            if (entity.body.speed.v[2] <= 0) {
                yscale = -1;
            }
        },
    }

    render.drawSpriteBillboard(Sprite.enemy_yellow, .{
        .frame = frame,
        .pos = entity.body.position,
        .angle = angle,
        .scale = .{ 1, yscale },
        .origin = .{ 0.5, if (yscale < 0) 1 else 0 },
    });

    // Render attack
    if (this.state == .plugged and this.time < attack_time) {
        Entity.Hitbox.drawRing(
            this.time,
            16,
            entity.body.position,
            attack_radius,
            attack_ring_thickness,
            Sprite.enemy_yellow.colors.back,
        );

        // Draw sparks
        if (this.time & 1 != 0) {
            for (0..3) |_| {
                angle = js.frandom(std.math.tau);

                const sprite = Sprite.attack_yellow;
                render.drawQuad(sprite.spr, .fromAtlas(sprite, .{
                    .size = .{ 50, attack_radius - attack_ring_thickness },
                    .origin = .{ 0.5, 0 },
                    .pos = entity.body.position.v,
                    .rot = .{ -std.math.pi / 2.0, 0, angle, 0 },
                }));
            }
        }
    }
}
