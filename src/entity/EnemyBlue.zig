const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");

points: [8]mtx.Vec2 = undefined,
wander_dir: f32 = 0,
lit: bool = false,
time: usize = 0,

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

    if (js.input.keys['E'].isPressed()) {
        explode(entity.body.position);
    }

    const player_distance = entity.distanceTo(Entity.Player.player);
    const player_direction = entity.directionTo(Entity.Player.player);

    if (this.time == 0) {
        this.time = (60 * 4) + js.irandom(60 * 4);
        const dir = js.frandom(1);
        this.wander_dir = player_direction + (dir * dir * std.math.tau * std.math.sign(dir - 0.5));
    }
    this.time -= 1;

    if (this.lit) {
        // Fuse particles
        if (Entity.findFree()) |particle| {
            const s: usize = 6 + js.irandom(4);
            Entity.Particle.init(particle, .{
                .sprite = Sprite.smoke.spr,
                .colors = Sprite.enemy_blue.colors,
                .pos = entity.body.position.add4(.init(0, 0, 12)),
                .speed = mtx.Vector.init(js.frandom(0.2), 0, 0.2 + js.frandom(0.1)).rotateZ(js.frandom(std.math.tau)),
                .w = s,
                .h = s,
                .time = 120,
                .scale_delta = -0.01 - js.frandom(0.01),
            });
        }

        // When explosion starts, create hitbox
        if (this.time == attack_time - 5) {
            if (Entity.findFree()) |hitbox| {
                Entity.Hitbox.init(hitbox, entity.body.position, attack_time - 5, attack_radius, 80);
            }
        }

        // Create explosion particles
        if (this.time <= attack_time) {
            explode(entity.body.position);
        }

        if (this.time == 0) {
            entity.flags.alive = false;
            return;
        }
    } else {
        entity.moveTowards(this.wander_dir, speed_accel, speed_max, 0);

        // Light fuse if near the player
        if (player_distance < light_distance) {
            this.lit = true;
            this.time = light_time;
            entity.body.speed = .zero;
        }
    }

    entity.body.moveAndCollide();
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.enemy_blue;

    var xscale: f32 = 1;

    const flash = (this.time >> 2) & 1 == 0;

    if (this.lit and flash) {
        if (this.time <= 60) xscale = 1.2;

        Entity.Hitbox.drawRing(
            this.time,
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

fn explode(pos: mtx.Vector) void {
    // Spawn 7 billion particles
    for (0..15) |_| {
        const particle = Entity.findFree() orelse break;

        const particle_dir = js.frandom(std.math.tau);
        const dist_rand = js.frandom(1);
        const dist_norm = dist_rand * dist_rand * dist_rand;

        const unit = mtx.Vector.init(
            1.0 - dist_norm + js.frandom(0.3),
            0,
            dist_norm * 0.5 + js.frandom(0.3),
        ).rotateZ(particle_dir);

        Entity.Particle.init(particle, .{
            .sprite = Sprite.smoke.spr,
            .colors = Sprite.enemy_blue.colors,
            .pos = unit.mulScalar4(10.0).add4(pos),
            .speed = unit.mulScalar4(7),
            .speed_damp = .init(0.95, 0.9, 1),
            .w = 16,
            .h = 16,
            .time = 120,
            .scale_delta = -0.01 - js.frandom(0.01),
        });
    }
}
