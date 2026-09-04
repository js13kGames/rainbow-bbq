const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const math = @import("math.zig");
const Camera = @import("camera.zig").CameraPerspective;

var matrix_storage: [256]math.Matrix = undefined;
pub var matrix_stack: std.ArrayList(math.Matrix) = .initBuffer(&matrix_storage);

var vertex_storage: [0x1000 * 6]js.Vertex = undefined;
var vertex_buffer: std.ArrayList(js.Vertex) = .initBuffer(&vertex_storage);

pub var camera: Camera = Camera{
    .z_near = 0.1,
    .z_far = 1000,
    .pitch_rad = -0.7,
    .position = .{ .v = .{ 20, -20, 40, 0 } },
};

pub const SpriteDescriptor = struct {
    size: [2]f32,
    origin: [2]f32 = .{ 0.5, 0.5 },
    pos: [2]f32 = .{ 0, 0 },
    angle: f32 = 0,
    color_back: [4]u8,
    color_fore: [4]u8,

    pub inline fn fromAtlas(comptime spr: anytype, mods: anytype) SpriteDescriptor {
        const desc: SpriteDescriptor = .{
            .size = .{ spr.w, spr.h },
            .color_back = spr.colors.back,
            .color_fore = spr.colors.fore,
        };

        return desc.edit(mods);
    }

    pub inline fn base(this: SpriteDescriptor, mods: anytype) SpriteDescriptor {
        const tinfo = @typeInfo(@TypeOf(mods)).@"struct";
        var out: SpriteDescriptor = .{
            .size = this.size,
            .origin = this.origin,
            .color_back = this.color_back,
            .color_fore = this.color_fore,
        };

        inline for (tinfo.field_names) |field_name| {
            if (comptime std.mem.eql(u8, field_name, "scale")) {
                out.size[0] = mods.scale[0] * this.size[0];
                out.size[1] = mods.scale[1] * this.size[1];
            } else {
                @field(out, field_name) = @field(mods, field_name);
            }
        }

        return out;
    }

    pub inline fn edit(this: SpriteDescriptor, mods: anytype) SpriteDescriptor {
        const tinfo = @typeInfo(@TypeOf(mods)).@"struct";
        var out: SpriteDescriptor = this;

        inline for (tinfo.field_names) |field_name| {
            if (comptime std.mem.eql(u8, field_name, "scale")) {
                out.size[0] = mods.scale[0] * this.size[0];
                out.size[1] = mods.scale[1] * this.size[1];
            } else {
                @field(out, field_name) = @field(mods, field_name);
            }
        }

        return out;
    }
};

pub fn drawSprite(spr: *const Sprite, t: SpriteDescriptor) void {
    const w = t.size[0];
    const h = t.size[1];

    const len_x = t.origin[0] * w;
    const len_y = t.origin[1] * h;
    const len = @sqrt(len_x * len_x + len_y * len_y);
    const offset_angle = js.atan2(len_y, len_x) + t.angle;
    const x = t.pos[0] - len * js.cos(offset_angle);
    const y = t.pos[1] - len * js.sin(offset_angle);

    var mtx = math.Matrix.fromTransform2D(
        js.cos(t.angle) * w,
        js.sin(t.angle) * w,
        -js.sin(t.angle) * h,
        js.cos(t.angle) * h,
        x,
        y,
    );

    mtx.multiply(currentMatrix(), &mtx);

    var verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
    verts[0] = .{
        .pos = (math.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u0, spr.v0 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[1] = .{
        .pos = (math.Vector{ .v = .{ 1, 0, 0, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u1, spr.v0 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[2] = .{
        .pos = (math.Vector{ .v = .{ 0, 1, 0, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u0, spr.v1 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[3] = .{
        .pos = (math.Vector{ .v = .{ 1, 1, 0, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u1, spr.v1 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };

    verts[4] = verts[2];
    verts[5] = verts[1];
}

pub const BillboardDescriptor = struct {
    size: [2]f32,
    origin: [2]f32 = .{ 0.5, 0.5 },
    pos: [3]f32 = .{ 0, 0, 0 },
    angle: f32 = 0,
    color_back: [4]u8 = .{ 0, 255, 0, 255 },
    color_fore: [4]u8 = .{ 255, 0, 0, 255 },
};

pub fn drawBillboard(spr: *const Sprite, t: BillboardDescriptor) void {
    const w = t.size[0];
    const h = t.size[1];

    var mtx = math.Matrix{};
    mtx
        .translate(t.pos[0], t.pos[1], t.pos[2])
        .rotateZ(camera.yaw_rad)
        .rotateY(t.angle)
        .translate(-t.origin[0] * w, 0, -t.origin[1] * h)
        .scale(w, 1, h)
        .multiply(currentMatrix(), &mtx);

    var verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
    verts[0] = .{
        .pos = (math.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u0, spr.v1 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[1] = .{
        .pos = (math.Vector{ .v = .{ 1, 0, 0, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u1, spr.v1 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[2] = .{
        .pos = (math.Vector{ .v = .{ 0, 0, 1, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u0, spr.v0 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[3] = .{
        .pos = (math.Vector{ .v = .{ 1, 0, 1, 1 } }).transform3(&mtx).v,
        .uv = .{ spr.u1, spr.v0 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };

    verts[4] = verts[2];
    verts[5] = verts[1];
}

pub fn drawCube(spr: *const Sprite) void {
    const mtx = currentMatrix();

    {
        const verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
        verts[0] = .{
            .pos = (math.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u0, spr.v0 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[1] = .{
            .pos = (math.Vector{ .v = .{ 1, 0, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u1, spr.v0 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[2] = .{
            .pos = (math.Vector{ .v = .{ 0, 1, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u0, spr.v1 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[3] = .{
            .pos = (math.Vector{ .v = .{ 1, 1, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u1, spr.v1 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };

        verts[4] = verts[2];
        verts[5] = verts[1];
    }

    {
        const verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
        verts[0] = .{
            .pos = (math.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u0, spr.v0 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[1] = .{
            .pos = (math.Vector{ .v = .{ 1, 0, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u1, spr.v0 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[2] = .{
            .pos = (math.Vector{ .v = .{ 0, 0, 1, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u0, spr.v1 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[3] = .{
            .pos = (math.Vector{ .v = .{ 1, 0, 1, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u1, spr.v1 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };

        verts[4] = verts[2];
        verts[5] = verts[1];
    }

    {
        const verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
        verts[0] = .{
            .pos = (math.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u0, spr.v0 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[1] = .{
            .pos = (math.Vector{ .v = .{ 0, 1, 0, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u1, spr.v0 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[2] = .{
            .pos = (math.Vector{ .v = .{ 0, 0, 1, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u0, spr.v1 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };
        verts[3] = .{
            .pos = (math.Vector{ .v = .{ 0, 1, 1, 1 } }).transform3(mtx).v,
            .uv = .{ spr.u1, spr.v1 },
            .color_back = .{ 255, 255, 255, 255 },
            .color_fore = .{ 0, 0, 0, 255 },
        };

        verts[4] = verts[2];
        verts[5] = verts[1];
    }
}

fn currentMatrix() *const math.Matrix {
    return &matrix_stack.items[matrix_stack.items.len - 1];
}

pub fn pushMatrix(mtx: *const math.Matrix) void {
    mtx.multiply(currentMatrix(), matrix_stack.addOneAssumeCapacity());
}

pub fn popMatrix() void {
    matrix_stack.items.len -= 1;
}

pub fn flush() void {
    js.draw(vertex_buffer.items);
    vertex_buffer.items.len = 0;
}
