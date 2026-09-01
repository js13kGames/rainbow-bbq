const std = @import("std");

const Matrix = @import("math.zig").Matrix;

/// TODO: eye position
pub const CameraOrtho = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    z_near: f32,
    z_far: f32,

    pub fn getMatrix(this: *const @This()) Matrix {
        return Matrix.orthoWebGL(
            this.x - this.width / 2,
            this.x + this.width / 2,
            -this.y + this.height / 2,
            -this.y - this.height / 2,
            this.z_near,
            this.z_far,
        );
    }
};

pub const Camera2D = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    z_near: f32,
    z_far: f32,

    pub fn getMatrix(this: *const @This()) Matrix {
        var mat = Matrix{};
        mat.scale(2 / this.width, 2 / -this.height, 1);
        mat.translate(-this.x, this.y, 0);
        return mat;
    }
};
