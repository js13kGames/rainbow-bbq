const std = @import("std");
const js = @import("js.zig");
const math = @import("math.zig");

var matrix_storage: [256]math.Matrix = undefined;
var matrix_stack: std.ArrayList(math.Matrix) = .initBuffer(&matrix_storage);

var vertex_storage: [0x1000 * 6]js.Vertex = undefined;
var vertex_buffer: std.ArrayList(js.Vertex) = .initBuffer(&vertex_storage);

pub const Sprite = struct {
    s: @import("Sprite"),
    size: [2]f32,
    origin: [2]f32 = .{ 0, 0 },

    pub fn fromAtlas(comptime spr: anytype, ox: f32, oy: f32) Sprite {
        return .{
            .s = spr.spr.*,
            .size = .{ spr.w, spr.h },
            .origin = .{ ox, oy },
        };
    }

    pub const Transform = struct {
        pos: [2]f32 = .{ 0, 0 },
        scale: [2]f32 = .{ 1, 1 },
        angle: f32 = 0,
        color_back: [4]u8 = .{ 0, 255, 0, 255 },
        color_fore: [4]u8 = .{ 255, 0, 0, 255 },

        pub fn toMatrix(t: *const Transform) math.Matrix {
            return math.Matrix.fromTransform2D(
                js.cos(t.angle) * t.scale[0],
                js.sin(t.angle) * t.scale[0],
                -js.sin(t.angle) * t.scale[1],
                js.cos(t.angle) * t.scale[1],
                t.pos[0],
                t.pos[1],
            );
        }
    };

    pub fn draw(spr: *const Sprite, t: *const Transform) void {
        const w = spr.size[0];
        const h = spr.size[1];

        const len_x = spr.origin[0] * w * t.scale[0];
        const len_y = spr.origin[1] * h * t.scale[1];
        const len = @sqrt(len_x * len_x + len_y * len_y);
        const offset_angle = js.atan2(len_y, len_x) + t.angle;
        const x = t.pos[0] - len * js.cos(offset_angle);
        const y = t.pos[1] - len * js.sin(offset_angle);

        var mtx = math.Matrix.fromTransform2D(
            js.cos(t.angle) * t.scale[0],
            js.sin(t.angle) * t.scale[0],
            -js.sin(t.angle) * t.scale[1],
            js.cos(t.angle) * t.scale[1],
            x,
            y,
        );

        mtx.multiply(currentMatrix(), &mtx);

        var verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
        verts[0] = .{
            .pos = (math.Vector{ .v = .{ 0, 0, 0, 1 } }).transform3(&mtx).v,
            .uv = .{ spr.s.u0, spr.s.v0 },
            .color_back = t.color_back,
            .color_fore = t.color_fore,
        };
        verts[1] = .{
            .pos = (math.Vector{ .v = .{ w, 0, 0, 1 } }).transform3(&mtx).v,
            .uv = .{ spr.s.u1, spr.s.v0 },
            .color_back = t.color_back,
            .color_fore = t.color_fore,
        };
        verts[2] = .{
            .pos = (math.Vector{ .v = .{ 0, h, 0, 1 } }).transform3(&mtx).v,
            .uv = .{ spr.s.u0, spr.s.v1 },
            .color_back = t.color_back,
            .color_fore = t.color_fore,
        };
        verts[3] = .{
            .pos = (math.Vector{ .v = .{ w, h, 0, 1 } }).transform3(&mtx).v,
            .uv = .{ spr.s.u1, spr.s.v1 },
            .color_back = t.color_back,
            .color_fore = t.color_fore,
        };

        verts[4] = verts[2];
        verts[5] = verts[1];
    }
};

fn currentMatrix() *const math.Matrix {
    return &matrix_stack.items[matrix_stack.items.len - 1];
}

pub fn pushMatrix(mtx: *const math.Matrix) void {
    if (matrix_stack.items.len == 0) {
        const ptr = matrix_stack.addOneAssumeCapacity();
        ptr.* = mtx.*;
        return;
    }

    mtx.multiply(currentMatrix(), matrix_stack.addOneAssumeCapacity());
}

pub fn popMatrix() void {
    matrix_stack.items.len -= 1;
}

pub fn flush() void {
    js.draw(vertex_buffer.items);
    vertex_buffer.items.len = 0;
}
