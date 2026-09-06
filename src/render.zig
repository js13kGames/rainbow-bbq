const std = @import("std");
const Sprite = @import("Sprite");

const js = @import("js.zig");
const mtx = @import("mtx.zig");
const Camera = @import("camera.zig").CameraPerspective;
const collision = @import("collision.zig");

pub const Vertex = js.Vertex;

var matrix_storage: [256]mtx.Matrix = undefined;
pub var matrix_stack: std.ArrayList(mtx.Matrix) = .initBuffer(&matrix_storage);

var vertex_storage: [0x1000 * 6]js.Vertex = undefined;
pub var vertex_buffer: std.ArrayList(js.Vertex) = .initBuffer(&vertex_storage);

pub var camera: Camera = Camera{
    .z_near = 1,
    .z_far = std.math.inf(f32),
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

pub fn transformVector(vec: anytype) [4]f32 {
    const vector = switch (@TypeOf(vec)) {
        mtx.Vector => vec,
        [2]f32, mtx.Vec2 => mtx.Vector.init(vec[0], vec[1], 0),
        [3]f32, mtx.Vec3 => mtx.Vector.init(vec[0], vec[1], vec[2]),
        [4]f32, mtx.Vec4 => mtx.Vector{ .v = vec },

        else => @compileError("no, bad"),
    };

    return vector.transform3(currentMatrix()).v;
}

pub inline fn pushVertex(vertex: Vertex) void {
    var out = vertex;
    out.pos = mtx.Vector.init(out.pos[0], out.pos[1], out.pos[2]).transform3(currentMatrix()).v;
    vertex_buffer.appendAssumeCapacity(out);
}

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

pub inline fn drawSpriteBillboard(sprite: anytype, t: struct {
    frame: usize = 0,
    pos: mtx.Vector = .init(0, 0, 0),
    angle: f32 = 0,
    scale: [2]f32 = .{ 1, 1 },
    origin: [2]f32 = .{ 0.5, 0 },
}) void {
    drawQuad(sprite.spr.frame(t.frame), .{
        .pos = .{ t.pos.v[0], t.pos.v[1], t.pos.v[2] },
        .size = .{ @as(f32, sprite.w) * t.scale[0], @as(f32, sprite.h) * t.scale[1] },
        .color_back = sprite.frame_colors[t.frame].back,
        .color_fore = sprite.frame_colors[t.frame].fore,
        .origin = t.origin,
        .rot = .{ 0, t.angle, camera.yaw_rad },
    });
}

pub fn drawPolygon2D(polygon: *const collision.Polygon, color: [4]u8) void {
    const spr = Sprite.white.spr;

    // Draw sum quads
    const p0 = Vertex{
        .pos = transformVector(polygon.points[0]),
        .uv = .{ spr.u0, spr.v0 },
        .color_back = color,
        .color_fore = color,
    };
    var p1 = Vertex{
        .pos = transformVector(polygon.points[1]),
        .uv = .{ spr.u0, spr.v0 },
        .color_back = color,
        .color_fore = color,
    };

    for (polygon.points[2..]) |point| {
        const verts = vertex_buffer.addManyAsSliceAssumeCapacity(3);

        verts[0] = p0;
        verts[1] = p1;
        verts[2] = .{
            .pos = transformVector(point),
            .uv = .{ spr.u0, spr.v0 },
            .color_back = color,
            .color_fore = color,
        };

        p1 = verts[2];
    }
}

pub fn drawPolygon3D(polygon: *const collision.Polygon) void {
    const wall = Sprite.wall;
    const spr = wall.spr;

    // Draw walls first
    const last_point = polygon.points[polygon.points.len - 1];
    var vert_00 = Vertex{
        .pos = transformVector([3]f32{ last_point[0], last_point[1], polygon.z_max }),
        .uv = .{ spr.u0, spr.v0 },
        .color_back = wall.colors.back,
        .color_fore = wall.colors.fore,
    };
    var vert_01 = Vertex{
        .pos = transformVector([3]f32{ last_point[0], last_point[1], polygon.z_min }),
        .uv = .{ spr.u0, spr.v1 },
        .color_back = wall.colors.back,
        .color_fore = wall.colors.fore,
    };

    for (polygon.points) |point| {
        vert_00.uv[0] = spr.u0;
        vert_01.uv[0] = spr.u0;

        const vert_10 = Vertex{
            .pos = transformVector([3]f32{ point[0], point[1], polygon.z_max }),
            .uv = .{ spr.u1, spr.v0 },
            .color_back = wall.colors.back,
            .color_fore = wall.colors.fore,
        };
        const vert_11 = Vertex{
            .pos = transformVector([3]f32{ point[0], point[1], polygon.z_min }),
            .uv = .{ spr.u1, spr.v1 },
            .color_back = wall.colors.back,
            .color_fore = wall.colors.fore,
        };

        // Push verts
        const verts = vertex_buffer.addManyAsSliceAssumeCapacity(6);
        verts[0] = vert_00;
        verts[1] = vert_10;
        verts[2] = vert_01;
        verts[3] = vert_11;
        verts[4] = vert_01;
        verts[5] = vert_10;

        // Save for next iteration
        vert_00 = vert_10;
        vert_01 = vert_11;
    }
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
