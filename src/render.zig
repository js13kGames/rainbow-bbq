const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const mtx = @import("mtx.zig");
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

pub const QuadDescriptor = struct {
    size: [2]f32,
    origin: [2]f32 = .{ 0.5, 0.5 },
    pos: [3]f32 = .{ 0, 0, 0 },
    rot: [3]f32 = .{ 0, 0, 0 },
    color_back: [4]u8 = .{ 0, 255, 0, 255 },
    color_fore: [4]u8 = .{ 255, 0, 0, 255 },

    pub inline fn fromAtlas(comptime spr: anytype, mods: anytype) QuadDescriptor {
        const desc: QuadDescriptor = .{
            .size = .{ spr.w, spr.h },
            .color_back = spr.colors.back,
            .color_fore = spr.colors.fore,
        };

        return desc.edit(mods);
    }

    pub inline fn base(this: QuadDescriptor, mods: anytype) QuadDescriptor {
        const tinfo = @typeInfo(@TypeOf(mods)).@"struct";
        var out: QuadDescriptor = .{
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

    pub inline fn edit(this: QuadDescriptor, mods: anytype) QuadDescriptor {
        const tinfo = @typeInfo(@TypeOf(mods)).@"struct";
        var out: QuadDescriptor = this;

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

pub fn drawQuad(spr: *const Sprite, t: QuadDescriptor) void {
    const w = t.size[0];
    const h = t.size[1];

    var matrix = mtx.Matrix{};
    matrix
        .translate(t.pos[0], t.pos[1], t.pos[2])
        .rotateZ(t.rot[2])
        .rotateX(t.rot[0])
        .rotateY(t.rot[1])
        .translate(-t.origin[0] * w, 0, -t.origin[1] * h)
        .scale(w, 1, h)
        .multiply(currentMatrix(), &matrix);

    var verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
    verts[0] = .{
        .pos = (mtx.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(&matrix).v,
        .uv = .{ spr.u0, spr.v1 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[1] = .{
        .pos = (mtx.Vector{ .v = .{ 1, 0, 0, 1 } }).transform3(&matrix).v,
        .uv = .{ spr.u1, spr.v1 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[2] = .{
        .pos = (mtx.Vector{ .v = .{ 0, 0, 1, 1 } }).transform3(&matrix).v,
        .uv = .{ spr.u0, spr.v0 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };
    verts[3] = .{
        .pos = (mtx.Vector{ .v = .{ 1, 0, 1, 1 } }).transform3(&matrix).v,
        .uv = .{ spr.u1, spr.v0 },
        .color_back = t.color_back,
        .color_fore = t.color_fore,
    };

    verts[4] = verts[2];
    verts[5] = verts[1];
}

fn currentMatrix() *const mtx.Matrix {
    return &matrix_stack.items[matrix_stack.items.len - 1];
}

pub fn pushMatrix(matrix: *const mtx.Matrix) void {
    matrix.multiply(currentMatrix(), matrix_stack.addOneAssumeCapacity());
}

pub fn popMatrix() void {
    matrix_stack.items.len -= 1;
}

pub fn flush() void {
    js.draw(vertex_buffer.items);
    vertex_buffer.items.len = 0;
}
