const std = @import("std");

pub const Matrix = struct {
    const Row = @Vector(4, f32);

    /// Each row can be bit-cast to @Vector(4, f32) for SIMD purposes
    m: [4][4]f32 = .{
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
            out.m[i] = @as(
                [4]f32,
                @as(Row, @splat(m[0])) * @as(Row, temp[0]) +
                    @as(Row, @splat(m[1])) * @as(Row, temp[1]) +
                    @as(Row, @splat(m[2])) * @as(Row, temp[2]) +
                    @as(Row, @splat(m[3])) * @as(Row, temp[3]),
            );
        }

        dest.* = out;
    }

    /// Translates a matrix in place
    pub fn translate(this: *Matrix, x: f32, y: f32, z: f32) void {
        this.m[3] = @as(
            [4]f32,
            @as(Row, this.m[0]) * @as(Row, @splat(x)) +
                @as(Row, this.m[1]) * @as(Row, @splat(y)) +
                @as(Row, this.m[2]) * @as(Row, @splat(z)) +
                @as(Row, this.m[3]),
        );
    }

    /// Scales a matrix in place
    pub fn scale(this: *Matrix, x: f32, y: f32, z: f32) void {
        this.m[0] = @as([4]f32, @as(Row, this.m[0]) * @as(Row, @splat(x)));
        this.m[1] = @as([4]f32, @as(Row, this.m[1]) * @as(Row, @splat(y)));
        this.m[2] = @as([4]f32, @as(Row, this.m[2]) * @as(Row, @splat(z)));
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
};

pub const Vector = struct {
    const Vec = @Vector(4, f32);

    v: [4]f32 = .{ 0, 0, 0, 1 },

    /// Multiply by a matrix as a 3D vector.
    /// Assumes the w component of the vector is 1.0.
    pub fn transform3(this: Vector, mtx: *const Matrix) Vector {
        const x = @as(Vec, @splat(this.v[0]));
        const y = @as(Vec, @splat(this.v[1]));
        const z = @as(Vec, @splat(this.v[2]));
        const w = @as(Vec, @splat(this.v[3]));

        return .{ .v = @as(
            [4]f32,
            (@as(Vec, mtx.m[0]) * x + @as(Vec, mtx.m[1]) * y + @as(Vec, mtx.m[2]) * z + @as(Vec, mtx.m[3])) / w,
        ) };
    }

    /// Multiply by a Matrix as a 4D vector
    pub fn transform4(this: Vector, mtx: *const Matrix) Vector {
        const x = @as(Vec, @splat(this.v[0]));
        const y = @as(Vec, @splat(this.v[1]));
        const z = @as(Vec, @splat(this.v[2]));
        const w = @as(Vec, @splat(this.v[3]));

        return .{ .v = @as(
            [4]f32,
            @as(Vec, mtx.m[0]) * x + @as(Vec, mtx.m[1]) * y + @as(Vec, mtx.m[2]) * z + @as(Vec, mtx.m[3]) * w,
        ) };
    }
};
