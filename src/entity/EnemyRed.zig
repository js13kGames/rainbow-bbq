const EnemyRed = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");

const State = enum {
    idle,
    squat,
    jump,
};

points: [8]mtx.Vec2 = undefined,
time: usize = 0,
state: State = .idle,
jump_dir: f32 = 0,

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_red = .{} };
    const this = &entity.inner.enemy_red;

    entity.flags = .{ .alive = true, .enemy_kind = .red };
    entity.body = .initCircle(pos, &this.points, 8, 8);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.enemy_red;

    // Update
    switch (this.state) {
        .idle => {
            this.time += 1;

            if (this.time >= 90) {
                this.time = 0;
                this.state = .squat;
            }
        },

        .squat => {
            this.time += 1;

            if (this.time >= 60) {
                this.time = 0;
                this.state = .jump;

                // Get direction to player
                this.jump_dir = entity.directionTo(Entity.Player.player);
                entity.body.speed = mtx.Vector.init(2, 0, 2.6).rotateZ(this.jump_dir);
            }
        },

        else => {
            const temp = mtx.Vector.init(2, 0, 0).rotateZ(this.jump_dir);
            entity.body.speed.v[0] = temp.v[0];
            entity.body.speed.v[1] = temp.v[1];

            // Just keep going until we land
            if (entity.body.isGrounded()) {
                this.time = 0;
                this.state = .idle;

                entity.body.speed = .init(0, 0, 0);
            }
        },
    }

    // Update physics
    entity.body.doGravity();
    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_red;

    // Draw
    switch (this.state) {
        .idle => {
            const frame = (this.time >> 4) & 1;
            render.drawSpriteBillboard(Sprite.enemy_red, .{
                .pos = entity.body.position,
                .frame = frame,
            });
        },

        .squat => {
            const shake = (this.time >> 2) & 1;
            render.drawSpriteBillboard(Sprite.enemy_red, .{
                .pos = entity.body.position,
                .frame = 1,
                .origin = .{
                    0.5 + @as(f32, if (shake == 0) 0.06 else -0.06),
                    0,
                },
            });
        },

        else => {
            render.drawSpriteBillboard(Sprite.enemy_red, .{
                .pos = entity.body.position,
                .frame = 2,
            });
        },
    }
}
