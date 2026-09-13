const Player = @This();

const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");
const collision = @import("../collision.zig");

points: [8]mtx.Vec2 = undefined,
charge: f32 = 0.5,
charging: bool = false,
anim: f32 = 0,
particle_tick: usize = 0,
hp: usize = 3,
invuln_timer: usize = 0,

speared: [6]Entity.EnemyKind = undefined,
num_speared: usize = 0,

score: usize = 0,
score_multiply: usize = 1,
score_multiply_timer: usize = 0,
score_gain: usize = 0,

dead: bool = false,

/// Singleton instance
pub var player: *Entity = undefined;

const speed_accel_regular: f32 = 0.035;
const speed_max_regular: f32 = 1.6;

const speed_accel_charge: f32 = 0.07;
const speed_max_charge: f32 = 3.2;

const player_width = 14;
const player_height = 16;

const charge_speed_init: f32 = 2.4;
const invuln_time: usize = 110;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .player = .{} };
    const this = &entity.inner.player;

    entity.flags = .{ .alive = true };
    entity.body = .initCircle(pos, &this.points, player_height, player_width / 2.0);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };

    player = entity;
}

const rainbow_colors = [_]Sprite.Colors{
    Sprite.enemy_red.colors,
    Sprite.enemy_orange.colors,
    Sprite.enemy_yellow.colors,
    Sprite.enemy_green.colors,
    Sprite.enemy_blue.colors,
    Sprite.enemy_purple.colors,
};

pub fn update(entity: *Entity) void {
    const this = &entity.inner.player;

    if (!this.dead) {

        // Timer stuff
        if (this.invuln_timer != 0) this.invuln_timer -= 1;
        if (this.score_gain != 0) this.score_gain -= 1;
        if (this.score_multiply_timer != 0) {
            this.score_multiply_timer -= 1;
            if (this.score_multiply_timer == 0) {
                this.score_multiply = 1;
            }
        }

        // Collide with enemies
        for (&Entity.all) |*other| {
            if (!other.flags.alive or other.flags.hurt_player == .never) continue;
            if (collision.shapeOverlapSAT(&entity.body.shape, &other.body.shape) == null) continue;

            // Ok, how do we handle this?
            if (this.charging and other.flags.hurt_player == .regular) {
                other.flags.alive = false;

                this.score += 10 * this.score_multiply;
                this.score_gain = 15;

                if (this.num_speared < 6) {
                    this.speared[this.num_speared] = other.flags.enemy_kind.?;
                    this.num_speared += 1;
                }
            } else if (this.invuln_timer == 0) {
                this.hp -= 1;
                this.invuln_timer = invuln_time;
                if (this.hp == 0) {
                    this.dead = true;
                    for (0..80) |_| {
                        spawnParticle(entity, 2.2);
                    }
                }
            }
        }

        // Begin charge
        if (js.input.keys[js.input.key_shift].isPressed()) {
            entity.body.speed = mtx.Vector.init(0, charge_speed_init, 0).rotateZ(render.camera.yaw_rad);

            // Spawn sum particles
            for (0..18) |_| {
                spawnParticle(entity, 1.5);
            }
        }

        var speed_accel = speed_accel_regular;
        var speed_max = speed_max_regular;
        this.charging = js.input.keys[js.input.key_shift].isHeld();
        if (this.charging) {
            this.charge = @max(0, this.charge - 0.003);
            if (this.charge == 0) {
                this.charging = false;
            } else {
                spawnParticle(entity, 0.3);
                speed_accel = speed_accel_charge;
                speed_max = speed_max_charge;
            }
        } else {
            this.charge = @min(1, this.charge + 0.002);
        }

        // Prepare movement
        entity.moveTowards(render.camera.yaw_rad + std.math.pi / 2.0, speed_accel, speed_max, 0);
        if (js.input.keys[' '].isHeld() and collision.isOnFloor(&entity.body.shape)) {
            entity.body.speed.v[2] = 3;
            this.anim = 0;
        }

        // And now go
        entity.body.moveAndCollide();
        this.anim += entity.body.speed.length2();
    }

    // Move camera
    const camera_distance_h = 50;
    const camera_distance_v = 10;
    render.camera.position = entity.body.position.add4(
        mtx.Vector
            .init(0, -camera_distance_h, camera_distance_v)
            .rotateX(-0.4)
            .rotateZ(render.camera.yaw_rad),
    );
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.player;
    if (this.dead) return;

    var frame: usize = 0;
    if (this.charging) frame += 2;

    // Use air sprite?
    if (!entity.body.isGrounded() or @as(usize, @trunc(this.anim / 12.0)) & 1 != 0) {
        frame += 1;
    }

    const hurt_flash = this.invuln_timer & 2 != 0;

    // Render the thing
    if (!hurt_flash) {
        const sprite = Sprite.unicorn;
        render.drawQuad(sprite.spr.frame(frame), .fromAtlas(sprite, .{
            .pos = entity.body.position.v,
            .rot = .{ 0, 0, render.camera.yaw_rad, 0 },
            .origin = .{ 0.5, 0 },
        }));
    }
}

fn spawnParticle(entity: *Entity, speed: f32) void {
    const this = &entity.inner.player;
    const particle = Entity.findFree() orelse return;
    this.particle_tick += 1;

    Entity.Particle.init(particle, .{
        .w = 4,
        .time = 30,
        .pos = entity.body.position,
        .colors = rainbow_colors[this.particle_tick % 6],
        .speed = .init(
            js.frandom(speed * 2) - speed,
            js.frandom(speed * 2) - speed,
            js.frandom(speed * 2) - speed,
        ),
    });
}
