const std = @import("std");

const math = @import("math.zig");
const Matrix = math.Matrix;
const Vector = math.Vector;

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

pub const CameraPerspective = struct {
    position: Vector = .init(0, -2, 0),
    pitch_rad: f32 = 0,
    yaw_rad: f32 = 0, // -(std.math.pi - 0.001),

    fov_rad: f32 = 60.0 * (std.math.pi / 180.0),
    z_near: f32 = 0.1,
    z_far: f32 = 1000,

    pub fn getLookDirectionVector(this: CameraPerspective) Vector {
        return Vector.init(0, 1, 0)
            .rotateX(this.pitch_rad)
            .rotateZ(this.yaw_rad)
            .normalize3();
    }

    pub fn getMatrix(this: CameraPerspective) Matrix {
        const projection_matrix = Matrix.perspectiveWebGL(
            this.fov_rad,
            160.0 / 144.0,
            this.z_near,
            this.z_far,
        );

        const view_matrix = Matrix.lookAt(
            this.position,
            this.getLookDirectionVector().add3(this.position),
            .init(0, 0, 1),
        );

        var out: Matrix = undefined;
        view_matrix.multiply(&projection_matrix, &out);
        return out;
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
        return mat
            .scale(2 / this.width, 2 / -this.height, 1)
            .translate(-this.x, this.y, 0).*;
    }
};
