const std = @import("std");

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,

    pub fn init(x: f32, y: f32, z: f32) Vec3 {
        return .{ .x = x, .y = y, .z = z };
    }

    pub fn splat(v: f32) Vec3 {
        return .{ .x = v, .y = v, .z = v };
    }

    pub fn zero() Vec3 {
        return splat(0.0);
    }

    pub fn add(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
    }

    pub fn sub(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
    }

    pub fn mul(a: Vec3, b: Vec3) Vec3 {
        return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
    }

    pub fn scale(a: Vec3, s: f32) Vec3 {
        return .{ .x = a.x * s, .y = a.y * s, .z = a.z * s };
    }

    pub fn neg(a: Vec3) Vec3 {
        return .{ .x = -a.x, .y = -a.y, .z = -a.z };
    }

    pub fn dot(a: Vec3, b: Vec3) f32 {
        return a.x * b.x + a.y * b.y + a.z * b.z;
    }

    pub fn cross(a: Vec3, b: Vec3) Vec3 {
        return .{
            .x = a.y * b.z - a.z * b.y,
            .y = a.z * b.x - a.x * b.z,
            .z = a.x * b.y - a.y * b.x,
        };
    }

    pub fn lengthSq(a: Vec3) f32 {
        return dot(a, a);
    }

    pub fn length(a: Vec3) f32 {
        return @sqrt(lengthSq(a));
    }

    pub fn normalize(a: Vec3) Vec3 {
        return scale(a, 1.0 / length(a));
    }

    pub fn lerp(a: Vec3, b: Vec3, t: f32) Vec3 {
        return add(scale(a, 1.0 - t), scale(b, t));
    }

    pub fn reflect(v: Vec3, n: Vec3) Vec3 {
        return sub(v, scale(n, 2.0 * dot(v, n)));
    }

    // Returns null on total internal reflection.
    pub fn refract(v: Vec3, n: Vec3, eta: f32) ?Vec3 {
        const cos_theta = @min(dot(neg(v), n), 1.0);
        const r_perp = scale(add(v, scale(n, cos_theta)), eta);
        const r_perp_sq = lengthSq(r_perp);
        if (r_perp_sq > 1.0) return null;
        const r_parallel = scale(n, -@sqrt(1.0 - r_perp_sq));
        return add(r_perp, r_parallel);
    }

    pub fn nearZero(a: Vec3) bool {
        const eps = 1e-8;
        return @abs(a.x) < eps and @abs(a.y) < eps and @abs(a.z) < eps;
    }

    // Build an orthonormal basis (tangent, bitangent) around `n`.
    pub fn buildOrthoFrame(n: Vec3) [2]Vec3 {
        const t = if (@abs(n.x) > 0.9)
            Vec3.init(0, 1, 0)
        else
            Vec3.init(1, 0, 0);
        const b = normalize(cross(n, t));
        return .{ normalize(cross(b, n)), b };
    }

    // Transform from tangent space (z-up) to world space given normal n.
    pub fn toWorld(local: Vec3, n: Vec3) Vec3 {
        const frame = buildOrthoFrame(n);
        const t = frame[0];
        const b = frame[1];
        return add(add(scale(t, local.x), scale(b, local.y)), scale(n, local.z));
    }
};

test "vec3 basics" {
    const a = Vec3.init(1, 0, 0);
    const b = Vec3.init(0, 1, 0);
    const c = Vec3.cross(a, b);
    try std.testing.expectApproxEqAbs(c.z, 1.0, 1e-6);
    try std.testing.expectApproxEqAbs(Vec3.dot(a, b), 0.0, 1e-6);
    try std.testing.expectApproxEqAbs(Vec3.length(a), 1.0, 1e-6);
}
