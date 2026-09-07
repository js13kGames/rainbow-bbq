const EnemyYellow = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");

const State = enum {
    approach,
    approach_jump,
    charge,
    launch,
    plugged,
    recover,
};

points: [8]mtx.Vec2 = undefined,
time: usize = 0,
state: State = .approach,
approach_speed: mtx.Vector = .init(0, 0, 0),

const elec_time = 120;
const stuck_time = 70;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_yellow = .{} };
    const this = &entity.inner.enemy_yellow;

    entity.flags = .{ .alive = true, .enemy_kind = .yellow };
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
            const added_speed = mtx.Vector
                .init(speed_accel, 0, 0)
                .rotateZ(target_direction);

            // If speed changed, we MUST have collided with a wall!
            if (this.approach_speed.length2() != 0 and this.approach_speed.length2() > entity.body.speed.length2()) {
                // Ok, but is player in that direction?
                if (this.approach_speed.dot2(added_speed) > 0) {
                    this.state = .approach_jump;
                    entity.body.speed.v[2] = 2.6;
                }
            }

            entity.body.speed = entity.body.speed.add4(added_speed);

            // Cap speed
            const speed_len = entity.body.speed.length2();
            if (speed_len > speed_max) {
                const speed_dir = entity.body.speed.normalize2();
                entity.body.speed = speed_dir.mulScalar2(speed_max);
            }

            this.approach_speed = entity.body.speed;

            // Are we close yet? Initiate attack?
            if (entity.distanceTo(Entity.Player.player) < 80) {
                this.state = .charge;
                this.time = 0;
            }
        },

        .approach_jump => {
            entity.body.speed.v[0] = this.approach_speed.v[0];
            entity.body.speed.v[1] = this.approach_speed.v[1];
            if (entity.body.isGrounded()) {
                this.state = .approach;
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
                if (Entity.findFree()) |slot| {
                    Entity.AttackYellow.init(slot, entity.body.position, elec_time);
                    this.time = 0;
                }
            }
        },

        .plugged => {
            if (this.time == elec_time + stuck_time) {
                this.state = .approach_jump;
                this.approach_speed = .init(0, 0, 0);
                entity.body.speed = .init(0, 0, 2);
            }
        },

        else => {},
    }

    entity.body.doGravity();
    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_yellow;

    var angle: f32 = 0;
    var frame: usize = 0;
    var yscale: f32 = 1;
    angle = 0;

    switch (this.state) {
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

        else => {
            frame = 0;
            if ((this.time >> 4) & 1 == 1) {
                frame += 1;
                if ((this.time >> 5) & 1 == 1) frame += 1;
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
}
