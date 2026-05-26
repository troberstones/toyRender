const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;

// Column-major 4x4 matrix. Columns stored as [col][row].
pub const Mat4 = struct {
    cols: [4][4]f32,

    pub fn identity() Mat4 {
        return .{ .cols = .{
            .{ 1, 0, 0, 0 },
            .{ 0, 1, 0, 0 },
            .{ 0, 0, 1, 0 },
            .{ 0, 0, 0, 1 },
        } };
    }

    pub fn translate(tx: f32, ty: f32, tz: f32) Mat4 {
        var m = identity();
        m.cols[3][0] = tx;
        m.cols[3][1] = ty;
        m.cols[3][2] = tz;
        return m;
    }

    pub fn scale(sx: f32, sy: f32, sz: f32) Mat4 {
        var m = identity();
        m.cols[0][0] = sx;
        m.cols[1][1] = sy;
        m.cols[2][2] = sz;
        return m;
    }

    pub fn rotateX(angle: f32) Mat4 {
        var m = identity();
        const c = @cos(angle);
        const s = @sin(angle);
        m.cols[1][1] = c;
        m.cols[1][2] = s;
        m.cols[2][1] = -s;
        m.cols[2][2] = c;
        return m;
    }

    pub fn rotateY(angle: f32) Mat4 {
        var m = identity();
        const c = @cos(angle);
        const s = @sin(angle);
        m.cols[0][0] = c;
        m.cols[0][2] = -s;
        m.cols[2][0] = s;
        m.cols[2][2] = c;
        return m;
    }

    pub fn rotateZ(angle: f32) Mat4 {
        var m = identity();
        const c = @cos(angle);
        const s = @sin(angle);
        m.cols[0][0] = c;
        m.cols[0][1] = s;
        m.cols[1][0] = -s;
        m.cols[1][1] = c;
        return m;
    }

    pub fn mul(a: Mat4, b: Mat4) Mat4 {
        var result: Mat4 = undefined;
        for (0..4) |col| {
            for (0..4) |row| {
                var sum: f32 = 0.0;
                for (0..4) |k| {
                    sum += a.cols[k][row] * b.cols[col][k];
                }
                result.cols[col][row] = sum;
            }
        }
        return result;
    }

    pub fn transformPoint(m: Mat4, p: Vec3) Vec3 {
        return .{
            .x = m.cols[0][0] * p.x + m.cols[1][0] * p.y + m.cols[2][0] * p.z + m.cols[3][0],
            .y = m.cols[0][1] * p.x + m.cols[1][1] * p.y + m.cols[2][1] * p.z + m.cols[3][1],
            .z = m.cols[0][2] * p.x + m.cols[1][2] * p.y + m.cols[2][2] * p.z + m.cols[3][2],
        };
    }

    pub fn transformDirection(m: Mat4, d: Vec3) Vec3 {
        return .{
            .x = m.cols[0][0] * d.x + m.cols[1][0] * d.y + m.cols[2][0] * d.z,
            .y = m.cols[0][1] * d.x + m.cols[1][1] * d.y + m.cols[2][1] * d.z,
            .z = m.cols[0][2] * d.x + m.cols[1][2] * d.y + m.cols[2][2] * d.z,
        };
    }

    // Transform a normal by the inverse-transpose (for non-uniform scale correctness).
    pub fn transformNormal(m_inv: Mat4, n: Vec3) Vec3 {
        return Vec3.normalize(.{
            .x = m_inv.cols[0][0] * n.x + m_inv.cols[0][1] * n.y + m_inv.cols[0][2] * n.z,
            .y = m_inv.cols[1][0] * n.x + m_inv.cols[1][1] * n.y + m_inv.cols[1][2] * n.z,
            .z = m_inv.cols[2][0] * n.x + m_inv.cols[2][1] * n.y + m_inv.cols[2][2] * n.z,
        });
    }

    // Inverse for affine matrices (no perspective).
    pub fn inverse(m: Mat4) Mat4 {
        // TODO: implement full 4x4 inverse via cofactor expansion or LU
        _ = m;
        @panic("Mat4.inverse not yet implemented");
    }
};
