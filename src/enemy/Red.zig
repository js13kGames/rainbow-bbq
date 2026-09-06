const Red = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Enemy = @import("../Enemy.zig");
const render = @import("../render.zig");
const js = @import("../js.zig");
const mtx = @import("../mtx.zig");
const player = &@import("../Player.zig").player;

const State = enum {
    idle,
    squat,
    jump,
};

time: usize = 0,
state: State = .idle,
jump_dir: f32 = 0,

pub fn update(state: *Red) void {
    const state_union: *Enemy.Kind = @fieldParentPtr("red", state);
    const this: *Enemy = @alignCast(@fieldParentPtr("kind", state_union));

    // Update
    switch (state.state) {
        .idle => {
            state.time += 1;

            if (state.time >= 90) {
                state.time = 0;
                state.state = .squat;
            }
        },

        .squat => {
            state.time += 1;

            if (state.time >= 60) {
                state.time = 0;
                state.state = .jump;

                // Get direction to player
                state.jump_dir = js.atan2(
                    player.body.position.v[1] - this.body.position.v[1],
                    player.body.position.v[0] - this.body.position.v[0],
                );

                this.body.speed = mtx.Vector.init(2, 0, 2.4).rotateZ(state.jump_dir);
            }
        },

        else => {
            const temp = mtx.Vector.init(2, 0, 0).rotateZ(state.jump_dir);
            this.body.speed.v[0] = temp.v[0];
            this.body.speed.v[1] = temp.v[1];
            this.body.doGravity();

            // Just keep going until we land
            if (this.body.isGrounded()) {
                state.time = 0;
                state.state = .idle;

                this.body.speed = .init(0, 0, 0);
            }
        },
    }
}

pub fn draw(state: *const Red) void {
    const state_union: *const Enemy.Kind = @fieldParentPtr("red", state);
    const this: *const Enemy = @alignCast(@fieldParentPtr("kind", state_union));

    // Draw
    switch (state.state) {
        .idle => {
            const frame = (state.time >> 4) & 1;
            render.drawSpriteBillboard(Sprite.enemy_red, .{
                .pos = this.body.position,
                .frame = frame,
            });
        },

        .squat => {
            const shake = (state.time >> 2) & 1;
            render.drawSpriteBillboard(Sprite.enemy_red, .{
                .pos = this.body.position,
                .frame = 1,
                .origin = .{
                    0.5 + @as(f32, if (shake == 0) 0.06 else -0.06),
                    0,
                },
            });
        },

        else => {
            render.drawSpriteBillboard(Sprite.enemy_red, .{
                .pos = this.body.position,
                .frame = 2,
            });
        },
    }
}
