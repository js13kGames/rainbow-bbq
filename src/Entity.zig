pub const Entity = @This();

pub const Player = @import("entity/Player.zig");
pub const EnemyRed = @import("entity/EnemyRed.zig");
pub const EnemyYellow = @import("entity/EnemyYellow.zig");
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
    return js.atan2(
        other.body.position.v[1] - this.body.position.v[1],
        other.body.position.v[0] - this.body.position.v[0],
    );
}

pub fn distanceTo(this: *const Entity, other: *const Entity) f32 {
    return this.body.position.sub4(other.body.position).length3();
}
