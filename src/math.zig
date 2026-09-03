const std = @import("std");

const js = @import("js.zig");

const Vec4 = @Vector(4, f32);
const Vec3 = @Vector(3, f32);

pub const Matrix = struct {
    m: [4]Vec4 = .{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    },

    /// Multiply 2 matrices.
    /// It is safe for source and destination matrices to overlap.
    pub fn multiply(a: *const Matrix, b: *const Matrix, dest: *Matrix) void {
        const temp = b.m;

        var out: Matrix = undefined;
        for (a.m, 0..) |m, i| {
            out.m[i] =
                @as(Vec4, @splat(m[0])) * temp[0] +
                @as(Vec4, @splat(m[1])) * temp[1] +
                @as(Vec4, @splat(m[2])) * temp[2] +
                @as(Vec4, @splat(m[3])) * temp[3];
        }

        dest.* = out;
    }

    /// Translates a matrix in place
    pub fn translate(this: *Matrix, x: f32, y: f32, z: f32) void {
        this.m[3] =
            this.m[0] * @as(Vec4, @splat(x)) +
            this.m[1] * @as(Vec4, @splat(y)) +
            this.m[2] * @as(Vec4, @splat(z)) +
            this.m[3];
    }

    /// Scales a matrix in place
    pub fn scale(this: *Matrix, x: f32, y: f32, z: f32) void {
        this.m[0] = this.m[0] * @as(Vec4, @splat(x));
        this.m[1] = this.m[1] * @as(Vec4, @splat(y));
        this.m[2] = this.m[2] * @as(Vec4, @splat(z));
    }

    /// Create a new matrix from a translation
    pub fn fromTranslation(x: f32, y: f32, z: f32) Matrix {
        return .{ .m = .{
            .{},
            .{},
            .{},
            .{ x, y, z, 1 },
        } };
    }

    /// Creates a new matrix from a scale
    pub fn fromScale(x: f32, y: f32, z: f32) Matrix {
        return .{ .m = .{
            .{ x, 0, 0, 0 },
            .{ 0, y, 0, 0 },
            .{ 0, 0, z, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn fromTransform2D(a: f32, b: f32, c: f32, d: f32, e: f32, f: f32) Matrix {
        return .{ .m = .{
            .{ a, b, 0, 0 },
            .{ c, d, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ e, f, 0, 1 },
        } };
    }

    /// You get to decide the low bound of the clip space Z-dimension.
    pub fn perspective(comptime ndc_z_low: i1, fov_y_rad: f32, aspect: f32, z_near: f32, z_far: f32) Matrix {
        var out: Matrix = .{};
        const f: f32 = 1.0 / @tan(fov_y_rad / 2);

        out.m[0][0] = f / aspect;
        out.m[1][1] = f;
        out.m[2][3] = -1;
        out.m[3][3] = 0;

        switch (ndc_z_low) {
            0 => {
                if (!std.math.isPositiveInf(z_far)) {
                    const nf = 1 / (z_near - z_far);
                    out.m[2][2] = z_far * nf;
                    out.m[3][2] = z_far * z_near * nf;
                } else {
                    out.m[2][2] = -1;
                    out.m[3][2] = -z_near;
                }
            },

            -1 => {
                if (!std.math.isPositiveInf(z_far)) {
                    const nf = 1 / (z_near - z_far);
                    out.m[2][2] = (z_far + z_near) * nf;
                    out.m[3][2] = 2 * z_far * z_near * nf;
                } else {
                    out.m[2][2] = -1;
                    out.m[3][2] = -2 * z_near;
                }
            },
        }

        return out;
    }

    /// Clip space is [-1, 1] for X, Y and Z.
    pub fn perspectiveWebGL(fov_y_rad: f32, aspect: f32, z_near: f32, z_far: f32) Matrix {
        return perspective(-1, fov_y_rad, aspect, z_near, z_far);
    }

    /// Clip space is [-1, 1] for X and Y, but [0, 1] for Z.
    pub fn perspectiveWebGPU(fov_y_rad: f32, aspect: f32, z_near: f32, z_far: f32) Matrix {
        return perspective(0, fov_y_rad, aspect, z_near, z_far);
    }

    /// You get to decide the low bound of the clip space Z-dimension.
    pub fn ortho(comptime ndc_z_low: i1, left: f32, right: f32, bottom: f32, top: f32, z_near: f32, z_far: f32) Matrix {
        var out: Matrix = .{};

        const lr: f32 = 1.0 / (left - right);
        const bt: f32 = 1.0 / (bottom - top);
        const nf: f32 = 1.0 / (z_near - z_far);

        out.m[0][0] = -2 * lr;
        out.m[1][1] = -2 * bt;
        out.m[2][2] = switch (ndc_z_low) {
            -1 => 2 * nf,
            0 => nf,
        };

        out.m[3][0] = (left + right) * lr;
        out.m[3][1] = (top + bottom) * bt;
        out.m[3][2] = switch (ndc_z_low) {
            -1 => (z_far + z_near) * nf,
            0 => z_near * nf,
        };
        out.m[3][3] = 1;

        return out;
    }

    /// Clip space is [-1, 1] for X, Y and Z.
    pub fn orthoWebGL(left: f32, right: f32, bottom: f32, top: f32, z_near: f32, z_far: f32) Matrix {
        return ortho(-1, left, right, bottom, top, -z_near, -z_far);
    }

    /// Clip space is [-1, 1] for X and Y, but [0, 1] for Z.
    pub fn orthoWebGPU(left: f32, right: f32, bottom: f32, top: f32, z_near: f32, z_far: f32) Matrix {
        return ortho(0, left, right, bottom, top, z_near, z_far);
    }

    pub fn lookAt(eye: Vector, target: Vector, up: Vector) Matrix {
        const axis_z = eye.sub3(target).normalize3();
        const axis_x = up.cross(axis_z).normalize3();
        const axis_y = axis_z.cross(axis_x).normalize3();

        return .{ .m = .{
            .{ axis_x.v[0], axis_y.v[0], axis_z.v[0], 0 },
            .{ axis_x.v[1], axis_y.v[1], axis_z.v[1], 0 },
            .{ axis_x.v[2], axis_y.v[2], axis_z.v[2], 0 },
            .{ -(axis_x.dot3(eye)), -(axis_y.dot3(eye)), -(axis_z.dot3(eye)), 1 },
        } };
    }
};

pub const Vector = struct {
    v: Vec4 = .{ 0, 0, 0, 1 },

    pub fn init(x: f32, y: f32, z: f32) Vector {
        return .{ .v = .{ x, y, z, 1 } };
    }

    pub inline fn to3(this: Vector) Vec3 {
        return .{ this.v[0], this.v[1], this.v[2] };
    }

    /// Multiply by a matrix as a 3D vector.
    /// Assumes the w component of the vector is 1.0.
    pub fn transform3(this: Vector, mtx: *const Matrix) Vector {
        const x: Vec4 = @splat(this.v[0]);
        const y: Vec4 = @splat(this.v[1]);
        const z: Vec4 = @splat(this.v[2]);
        const w: Vec4 = @splat(this.v[3]);

        return .{ .v = (mtx.m[0] * x + mtx.m[1] * y + mtx.m[2] * z + mtx.m[3]) / w };
    }

    /// Multiply by a Matrix as a 4D vector
    pub fn transform4(this: Vector, mtx: *const Matrix) Vector {
        const x: Vec4 = @splat(this.v[0]);
        const y: Vec4 = @splat(this.v[1]);
        const z: Vec4 = @splat(this.v[2]);
        const w: Vec4 = @splat(this.v[3]);

        return .{ .v = mtx.m[0] * x + mtx.m[1] * y + mtx.m[2] * z + mtx.m[3] * w };
    }

    pub fn normalize3(this: Vector) Vector {
        const sqr = this.v * this.v;
        const len_sqr = sqr[0] + sqr[1] + sqr[2];
        const len_inv: f32 = 1.0 / @sqrt(len_sqr);
        var res = this.v * @as(Vec4, @splat(len_inv));
        res[3] = 1;
        return .{ .v = res };
    }

    pub fn add3(this: Vector, other: Vector) Vector {
        var r = this.v + other.v;
        r[3] = 1;
        return .{ .v = r };
    }

    pub fn add4(this: Vector, other: Vector) Vector {
        return .{ .v = this.v + other.v };
    }

    pub fn sub3(this: Vector, other: Vector) Vector {
        var r = this.v - other.v;
        r[3] = 1;
        return .{ .v = r };
    }

    pub fn sub4(this: Vector, other: Vector) Vector {
        return .{ .v = this.v - other.v };
    }

    pub fn rotateX(this: Vector, rad: f32) Vector {
        return .init(
            this.v[0],
            this.v[1] * js.cos(rad) - this.v[2] * js.sin(rad),
            this.v[1] * js.sin(rad) + this.v[2] * js.cos(rad),
        );
    }

    pub fn rotateY(this: Vector, rad: f32) Vector {
        return .init(
            this.v[2] * js.sin(rad) + this.v[0] * js.cos(rad),
            this.v[1],
            this.v[2] * js.cos(rad) - this.v[0] * js.sin(rad),
        );
    }

    pub fn rotateZ(this: Vector, rad: f32) Vector {
        return .init(
            this.v[0] * js.cos(rad) - this.v[1] * js.sin(rad),
            this.v[0] * js.sin(rad) + this.v[1] * js.cos(rad),
            this.v[2],
        );
    }

    pub fn dot3(this: Vector, other: Vector) f32 {
        const r = this.v * other.v;
        return r[0] + r[1] + r[2];
    }

    pub fn cross(this: Vector, other: Vector) Vector {
        const tmp0: Vec4 = .{ this.v[1], this.v[2], this.v[0], 1 };
        const tmp1: Vec4 = .{ other.v[2], other.v[0], other.v[1], 1 };
        const tmp2: Vec4 = .{ this.v[2], this.v[0], this.v[1], 1 };
        const tmp3: Vec4 = .{ other.v[1], other.v[2], other.v[0], 1 };

        return .{ .v = (tmp0 * tmp1) - (tmp2 * tmp3) };
    }
};
