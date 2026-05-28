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

    // Exact comparison against the identity matrix. Identity transforms are
    // constructed with exact 0.0/1.0, so equality is reliable here.
    pub fn isIdentity(m: Mat4) bool {
        const id = identity();
        for (0..4) |c| {
            for (0..4) |r| {
                if (m.cols[c][r] != id.cols[c][r]) return false;
            }
        }
        return true;
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

    // Inverse for affine matrices (no perspective) via 3x3 cofactor expansion.
    pub fn inverse(m: Mat4) Mat4 {
        // Extract 3x3 linear submatrix; a[row][col] = m.cols[col][row].
        const a00 = m.cols[0][0]; const a01 = m.cols[1][0]; const a02 = m.cols[2][0];
        const a10 = m.cols[0][1]; const a11 = m.cols[1][1]; const a12 = m.cols[2][1];
        const a20 = m.cols[0][2]; const a21 = m.cols[1][2]; const a22 = m.cols[2][2];

        // Cofactors (signed minors) of A.
        const c00 =  (a11 * a22 - a12 * a21);
        const c01 = -(a10 * a22 - a12 * a20);
        const c02 =  (a10 * a21 - a11 * a20);
        const c10 = -(a01 * a22 - a02 * a21);
        const c11 =  (a00 * a22 - a02 * a20);
        const c12 = -(a00 * a21 - a01 * a20);
        const c20 =  (a01 * a12 - a02 * a11);
        const c21 = -(a00 * a12 - a02 * a10);
        const c22 =  (a00 * a11 - a01 * a10);

        const det = a00 * c00 + a01 * c01 + a02 * c02;
        const s = 1.0 / det;

        // A_inv[row][col] = cofactor(col, row) / det — stored column-major.
        var r = Mat4.identity();
        r.cols[0][0] = c00 * s; r.cols[0][1] = c01 * s; r.cols[0][2] = c02 * s;
        r.cols[1][0] = c10 * s; r.cols[1][1] = c11 * s; r.cols[1][2] = c12 * s;
        r.cols[2][0] = c20 * s; r.cols[2][1] = c21 * s; r.cols[2][2] = c22 * s;

        // Translation: t_inv = -A_inv * t
        const tx = m.cols[3][0]; const ty = m.cols[3][1]; const tz = m.cols[3][2];
        r.cols[3][0] = -(r.cols[0][0] * tx + r.cols[1][0] * ty + r.cols[2][0] * tz);
        r.cols[3][1] = -(r.cols[0][1] * tx + r.cols[1][1] * ty + r.cols[2][1] * tz);
        r.cols[3][2] = -(r.cols[0][2] * tx + r.cols[1][2] * ty + r.cols[2][2] * tz);
        return r;
    }

    // Camera-to-world look-at transform.  The camera looks along -Z in camera space
    // (matching the PinholeCamera ray direction convention).
    pub fn lookAt(from: Vec3, to: Vec3, up: Vec3) Mat4 {
        const fwd = Vec3.normalize(Vec3.sub(to, from));
        const r   = Vec3.normalize(Vec3.cross(fwd, up));
        const u   = Vec3.cross(r, fwd);
        return .{ .cols = .{
            .{ r.x,    r.y,    r.z,    0 },
            .{ u.x,    u.y,    u.z,    0 },
            .{ -fwd.x, -fwd.y, -fwd.z, 0 },
            .{ from.x, from.y, from.z, 1 },
        }};
    }
};
