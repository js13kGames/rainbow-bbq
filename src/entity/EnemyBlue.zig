const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [8]mtx.Vec2 = undefined,
wandering: Entity.Wandering = .{},
lit: bool = false,

const speed_accel: f32 = 0.002;
const speed_max: f32 = 0.5;
const light_distance: f32 = 140;
const light_time: usize = 60 * 3 + attack_time;

const attack_time: usize = 20;
const attack_radius: f32 = 120;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .enemy_blue = .{} };
    const this = &entity.inner.enemy_blue;

    entity.flags = .{ .alive = true, .enemy_kind = .blue, .hurt_player = .regular };
    entity.body = .initCircle(pos, &this.points, 17, 11);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.enemy_blue;

    if (this.lit) {
        // Fuse particles
        spawnParticle(entity.body.position, 1);
        this.wandering.wander_time -= 1;

        // When explosion starts, create hitbox
        if (this.wandering.wander_time == attack_time - 5) {
            if (Entity.findFree()) |hitbox| {
                Entity.Hitbox.init(hitbox, entity.body.position, attack_time - 5, attack_radius, 80);
            }
        }

        // Create explosion particles
        if (this.wandering.wander_time <= attack_time) {
            for (0..15) |_| {
                spawnParticle(entity.body.position, 10);
            }
        }

        if (this.wandering.wander_time == 0) {
            entity.flags.alive = false;
            return;
        }
    } else {
        const is_near = entity.wander(&this.wandering);

        // Light fuse if near the player
        if (is_near) {
            this.lit = true;
            this.wandering.wander_time = light_time;
            entity.body.speed = .zero;
        }
    }

    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_blue;

    var xscale: f32 = 1;

    const flash = (this.wandering.wander_time >> 2) & 1 == 0;

    if (this.lit and flash) {
        if (this.wandering.wander_time <= 60) xscale = 1.2;

        Entity.Hitbox.drawRing(
            this.wandering.wander_time,
            16,
            entity.body.position.add4(.init(0, 0, 1)),
            attack_radius,
            8,
            Sprite.enemy_blue.colors.back,
        );
    }

    render.drawSpriteBillboard(Sprite.enemy_blue, .{
        .pos = entity.body.position,
        .scale = .{ xscale, xscale },
    });
}

fn spawnParticle(pos: mtx.Vector, speed: f32) void {
    // Spawn 7 billion particles
    const particle = Entity.findFree() orelse return;

    const particle_dir = js.frandom(std.math.tau);
    const dist_rand = js.frandom(1);
    const dist_norm = dist_rand * dist_rand * dist_rand;

    const unit = mtx.Vector.init(
        1.0 - dist_norm + js.frandom(0.3),
        0,
        dist_norm * 0.5 + js.frandom(0.3),
    ).rotateZ(particle_dir);

    Entity.Particle.init(particle, .{
        .colors = Sprite.enemy_blue.colors,
        .pos = unit.mulScalar4(10.0).add4(pos),
        .speed = unit.mulScalar4(speed),
        .speed_damp = .init(0.95, 0.9, 1),
        .w = 16,
        .time = 120,
        .scale_delta = -0.01 - js.frandom(0.01),
    });
}
