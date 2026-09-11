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

    // Hurt stuff
    if (this.invuln_timer != 0) this.invuln_timer -= 1;

    // Collide with enemies
    for (&Entity.all) |*other| {
        if (!other.flags.alive or other.flags.hurt_player == .never) continue;
        if (collision.shapeOverlapSAT(&entity.body.shape, &other.body.shape) == null) continue;

        // Ok, how do we handle this?
        if (this.charging and other.flags.hurt_player == .regular) {
            other.flags.alive = false;
            std.log.info("kill {}", .{std.meta.activeTag(other.inner)});
        } else if (this.invuln_timer == 0) {
            this.hp -= 1;
            this.invuln_timer = invuln_time;
            std.log.warn("hurt by {}", .{std.meta.activeTag(other.inner)});
        }
    }

    // Begin charge
    if (js.input.keys[js.input.key_shift].isPressed()) {
        entity.body.speed = mtx.Vector.init(0, charge_speed_init, 0).rotateZ(render.camera.yaw_rad);

        // Spawn sum particles
        for (0..12) |_| {
            spawnParticle(entity, 1);
        }
    }

    var speed_accel = speed_accel_regular;
    var speed_max = speed_max_regular;
    this.charging = js.input.keys[js.input.key_shift].isHeld();
    if (this.charging) {
        spawnParticle(entity, 0.3);
        speed_accel = speed_accel_charge;
        speed_max = speed_max_charge;
    }

    // Prepare movement
    entity.moveTowards(render.camera.yaw_rad + std.math.pi / 2.0, speed_accel, speed_max, 0);
    if (js.input.keys[' '].isHeld() and entity.body.speed.v[2] <= 0 and collision.isOnFloor(&entity.body.shape)) {
        entity.body.speed.v[2] = 3;
        this.anim = 0;
    }

    // And now go
    entity.body.moveAndCollide();
    this.anim += entity.body.speed.length2();

    // Move camera
    const camera_distance_h = 50;
    const camera_distance_v = 10;
    render.camera.position = entity.body.position.add4(
        mtx.Vector
            .init(0, -camera_distance_h, camera_distance_v)
            .rotateX(render.camera.pitch_rad)
            .rotateZ(render.camera.yaw_rad),
    );
    render.camera.position.v[3] = 1;
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.player;

    var frame: usize = 0;
    if (this.charging) frame = 2;

    // Use air sprite?
    if (!entity.body.isGrounded() or @as(usize, @trunc(this.anim / 12.0)) & 1 != 0) {
        frame += 1;
    }

    const hurt_flash = this.invuln_timer & 2 != 0;

    // Render the thing
    if (!hurt_flash) {
        const sprite = Sprite.unicorn;
        render.drawQuad(sprite.spr.frame(frame), .fromAtlas(sprite, .{
            .pos = .{ entity.body.position.v[0], entity.body.position.v[1], entity.body.position.v[2] },
            .rot = .{ 0, 0, render.camera.yaw_rad },
            .origin = .{ 0.5, 0 },
        }));
    }
}

fn spawnParticle(entity: *Entity, speed: f32) void {
    const this = &entity.inner.player;
    const particle = Entity.findFree() orelse return;
    this.particle_tick += 1;

    Entity.Particle.init(particle, .{
        .sprite = Sprite.smoke.spr,
        .w = 4,
        .h = 4,
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
