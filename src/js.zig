//! Contains all the stuff needed for the JS -> Zig bridge

const std = @import("std");

const render = @import("render.zig");

pub inline fn log(log_level: std.log.Level, str: []const u8) void {
    struct {
        extern "1" fn log(log_level: u32, str_start: [*]const u8, str_len: usize) void;
    }.log(@intFromEnum(log_level), str.ptr, str.len);
}

pub const Vertex = extern struct {
    pos: [4]f32,
    uv: [2]f32,
    color_back: [4]u8,
    color_fore: [4]u8,
};

pub inline fn draw(vertices: []const Vertex) void {
    struct {
        extern "2" fn draw(vertex_ptr: [*]const Vertex, vertex_len: usize) void;
    }.draw(vertices.ptr, vertices.len);
}

pub inline fn uploadTexture(data: []const u8, width: usize, height: usize) void {
    struct {
        extern "3" fn uploadTexture(data_ptr: [*]const u8, width: usize, height: usize) void;
    }.uploadTexture(data.ptr, width, height);
}

pub extern "4" fn atan2(y: f32, x: f32) f32;
pub extern "5" fn sin(v: f32) f32;
pub extern "6" fn cos(v: f32) f32;
pub extern "7" fn tan(v: f32) f32;
pub extern "8" fn frandom(max: f32) f32;
pub extern "8" fn irandom(max: usize) usize;

/// Initialize a piece of static memory.
/// It is not possible to free this memory.
pub inline fn staticAlloc(comptime T: type, comptime size: usize) []T {
    const page_count = comptime page_size: {
        const byte_count = size * @sizeOf(T);
        if (byte_count & 0xFFFF == 0) {
            break :page_size byte_count >> 16;
        } else {
            break :page_size (byte_count >> 16) + 1;
        }
    };
    std.debug.assert(page_count > 0);

    const old_size = @wasmMemoryGrow(0, page_count);
    std.debug.assert(old_size > 0);

    var slice: []T = undefined;
    slice.ptr = @ptrFromInt(@as(usize, @bitCast(old_size << 16)));
    slice.len = size;
    return slice;
}

/// Keyboard input
export fn k(key: usize, pressed: bool) void {
    input.keys[key].next = pressed;
}

export fn m(dx: f32, dy: f32) void {
    input.mouse_nx += dx;
    input.mouse_ny += dy;
}

pub const input = struct {
    pub var keys: [256]DigitalState = undefined;

    var mouse_nx: f32 = 0;
    var mouse_ny: f32 = 0;

    pub const DigitalState = packed struct(u8) {
        previous: bool = false,
        current: bool = false,
        next: bool = false,
        _: u5 = 0,

        pub fn isHeld(self: DigitalState) bool {
            return self.current;
        }

        pub fn isPressed(self: DigitalState) bool {
            return self.current and !self.previous;
        }

        pub fn isReleased(self: DigitalState) bool {
            return !self.current and self.previous;
        }

        pub fn update(key: DigitalState) DigitalState {
            var out = key;
            out.previous = key.current;
            out.current = key.next;
            return out;
        }
    };

    pub fn update() void {
        render.camera.yaw_rad -= mouse_nx / 300.0;
        mouse_nx = 0;

        render.camera.pitch_rad -= mouse_ny / 300.0;
        render.camera.pitch_rad = @min(@max(render.camera.pitch_rad, -std.math.pi / 2.01), std.math.pi / 2.01);
        mouse_ny = 0;

        for (&keys, 0..) |key, i| {
            keys[i] = key.update();
        }
    }
};
