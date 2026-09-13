const std = @import("std");
const Sprite = @import("Sprite");

const Entity = @import("../Entity.zig");
const render = @import("../render.zig");
const mtx = @import("../mtx.zig");
const js = @import("../js.zig");
const collision = @import("../collision.zig");

points: [8]mtx.Vec2 = undefined,
time: usize = 0,
content: ?[6]Entity.EnemyKind = null,

const radius: f32 = 30;
const grill_time: usize = 60 * 10;

pub fn init(entity: *Entity, pos: mtx.Vector) void {
    entity.inner = .{ .grill = .{} };
    const this = &entity.inner.grill;

    entity.flags = .{ .alive = true };
    entity.body = .initCircle(pos, &this.points, 48, radius);

    entity.vtable = .{
        .update = update,
        .draw = draw,
    };
}

pub fn update(entity: *Entity) void {
    const this = &entity.inner.grill;
    this.time += 1;

    const player = &Entity.Player.player.inner.player;

    // Take stuff off the grill
    if (this.content == null) {
        if (collision.shapeOverlapSAT(&entity.body.shape, &Entity.Player.player.body.shape) != null and player.num_speared == 6) {
            this.content = player.speared;
            player.num_speared = 0;
            this.time = 0;
            if (Entity.findFree()) |result| {
                Entity.GrillResult.init(result, player.speared);
            }
        }
    }

    // Put stuff onto the grill
    else if (this.time >= grill_time) {
        this.content = null;
    }
}

pub fn draw(entity: *const Entity) void {
    const this = &entity.inner.grill;

    render.drawSpriteBillboard(Sprite.grill, .{
        .pos = entity.body.position,
    });

    const siner = js.sin(@as(f32, @floatFromInt(this.time)) / 16.0);

    if ((this.content == null and Entity.Player.player.inner.player.num_speared == 6) or (this.content != null and this.time > grill_time)) {
        // Arrow
        render.drawSpriteBillboard(Sprite.arrow, .{
            .angle = std.math.pi * 0.5,
            .origin = .{ 0.5, 0.5 },
            .pos = entity.body.position.add4(.init(0, 0, 48 + siner * 6)),
        });
    } else if (this.content != null and this.time < grill_time) {
        // Sizzle
        const xscale: f32 = if (this.time & 16 == 0) 1 else -1;
        render.drawSpriteBillboard(Sprite.sizzle, .{
            .origin = .{ 0.5, 0.5 },
            .pos = entity.body.position.add4(.init(0, 0, 48 + siner * 3)),
            .scale = .{ xscale, 1 },
        });
    }

    if (this.content) |content| {
        drawSpear(
            entity.body.position.add3(.init(0, 0, 30)),
            .{ 0, std.math.pi / 2.0, std.math.pi / 2.0 },
            &content,
            0,
        );
    }
}

const EnemySpriteDesc = struct {
    spr: *const Sprite,
    color: u32,

    pub fn fromAtlas(sprite: anytype) EnemySpriteDesc {
        return .{
            .spr = sprite.spr,
            .color = sprite.colors.back,
        };
    }
};

pub const sprite_map = std.EnumArray(Entity.EnemyKind, EnemySpriteDesc).init(.{
    .red = .fromAtlas(Sprite.enemy_red),
    .green = .fromAtlas(Sprite.enemy_green),
    .blue = .fromAtlas(Sprite.enemy_blue),
    .yellow = .fromAtlas(Sprite.enemy_yellow),
    .purple = .fromAtlas(Sprite.enemy_purple),
    .orange = .fromAtlas(Sprite.enemy_orange),
});

pub fn drawSpear(pos: mtx.Vector, angle: [3]f32, content: []const Entity.EnemyKind, content_angle: f32) void {
    const horn_sprite = Sprite.horn;

    var matrix = mtx.Matrix{};
    _ = matrix
        .translate(pos.v[0], pos.v[1], pos.v[2])
        .rotateZ(angle[2])
        .rotateX(angle[0])
        .rotateY(angle[1]);
    render.pushMatrix(&matrix);
    defer render.popMatrix();

    var horn_desc: render.QuadDescriptor = .fromAtlas(horn_sprite, .{});
    render.drawQuad(horn_sprite.spr, horn_desc);

    horn_desc.rot[2] += std.math.pi;
    render.drawQuad(horn_sprite.spr, horn_desc);

    var matrix2 = mtx.Matrix{};
    _ = matrix2
        .rotateZ(std.math.pi / 2.0)
        .rotateX(-std.math.pi / 2.0);

    render.pushMatrix(&matrix2);
    defer render.popMatrix();

    for (content, 0..) |item, i| {
        const t = sprite_map.get(item);
        const mr = std.math.pi / 16.0;
        const mpos = mtx.Vector.init(0, 20 - @as(f32, @floatFromInt(i * 8)), 0);

        var desc: render.QuadDescriptor = .{
            .size = .{ 20, 20 },
            .color_back = t.color,
            .color_fore = render.buildColor(.{ 0, 0, 0, 255 }),
            .pos = mpos.v,
            .rot = .{ mr, mr, mr + content_angle, 0 },
        };
        render.drawQuad(t.spr, desc);

        desc.rot[0] += std.math.pi;
        desc.rot[1] += std.math.pi;
        render.drawQuad(t.spr, desc);
    }
}
