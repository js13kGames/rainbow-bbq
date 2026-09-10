pub const Entity = @This();

pub const Player = @import("entity/Player.zig");
pub const EnemyRed = @import("entity/EnemyRed.zig");
pub const EnemyYellow = @import("entity/EnemyYellow.zig");
pub const EnemyGreen = @import("entity/EnemyGreen.zig");
pub const EnemyOrange = @import("entity/EnemyOrange.zig");
pub const EnemyPurple = @import("entity/EnemyPurple.zig");

pub const Particle = @import("entity/Particle.zig");
pub const AttackYellow = @import("entity/AttackYellow.zig");

const collision = @import("collision.zig");
const mtx = @import("mtx.zig");
const js = @import("js.zig");

pub const EnemyKind = enum {
    red,
    yellow,
    blue,
    green,
    orange,
    purple,
};

pub const Flags = struct {
    /// Is this entity is allocated
    alive: bool = false,

    /// Is this entity an enemy, and what kind?
    enemy_kind: ?EnemyKind = null,

    /// Does this entity hurt the player on contact?
    hurt_player: bool = false,
};

pub const VTable = struct {
    update: *const fn (entity: *Entity) void,
    draw: *const fn (entity: *const Entity) void,
};

body: collision.PhysicsEntity,
flags: Flags,

vtable: VTable,

/// Union is required to figure out how much memory to allocate
inner: union {
    none: void,
    player: Player,
    enemy_red: EnemyRed,
    enemy_yellow: EnemyYellow,
    enemy_green: EnemyGreen,
    enemy_orange: EnemyOrange,
    enemy_purple: EnemyPurple,

    particle: Particle,
    attack_yellow: AttackYellow,
},

pub var all: [1024]Entity = undefined;

pub fn initAll() void {
    for (&all) |*entity| {
        entity.flags.alive = false;
    }
}

pub fn update(this: *Entity) void {
    if (!this.flags.alive) return;
    this.vtable.update(this);
}

pub fn draw(this: *const Entity) void {
    if (!this.flags.alive) return;
    this.vtable.draw(this);
}

pub fn findFree() ?*Entity {
    for (&all) |*entity| {
        if (!entity.flags.alive) return entity;
    }

    return null;
}

pub fn directionTo(this: *const Entity, other: *const Entity) f32 {
    return other.body.position.sub4(this.body.position).direction2();
}

pub fn distanceTo(this: *const Entity, other: *const Entity) f32 {
    return this.body.position.sub4(other.body.position).length3();
}

pub fn moveTowards(this: *Entity, direction: f32, accel: f32, max_speed: f32, jump_force: f32) void {
    // That's the direction we want to go
    const added_speed = mtx.Vector
        .init(accel, 0, 0)
        .rotateZ(direction);

    // If speed changed, we MUST have collided with a wall!
    if (this.body.collided and this.body.isGrounded()) {
        this.body.speed.v[2] = jump_force;
    }

    this.body.speed = this.body.speed.add4(added_speed);

    // Cap speed
    const speed_len = this.body.speed.length2();
    if (speed_len > max_speed) {
        const speed_dir = this.body.speed.normalize2();
        this.body.speed = speed_dir.mulScalar2(max_speed);
    }
}
