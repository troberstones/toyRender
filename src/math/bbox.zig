const std = @import("std");
const Vec3 = @import("vec3.zig").Vec3;
const Ray = @import("ray.zig").Ray;

pub const AABB = struct {
    min: Vec3,
    max: Vec3,

    pub fn empty() AABB {
        const inf = std.math.floatMax(f32);
        return .{
            .min = Vec3.splat(inf),
            .max = Vec3.splat(-inf),
        };
    }

    pub fn fromPoints(a: Vec3, b: Vec3) AABB {
        return .{
            .min = Vec3.init(@min(a.x, b.x), @min(a.y, b.y), @min(a.z, b.z)),
            .max = Vec3.init(@max(a.x, b.x), @max(a.y, b.y), @max(a.z, b.z)),
        };
    }

    pub fn expand(a: AABB, b: AABB) AABB {
        return .{
            .min = Vec3.init(@min(a.min.x, b.min.x), @min(a.min.y, b.min.y), @min(a.min.z, b.min.z)),
            .max = Vec3.init(@max(a.max.x, b.max.x), @max(a.max.y, b.max.y), @max(a.max.z, b.max.z)),
        };
    }

    pub fn expandPoint(self: AABB, p: Vec3) AABB {
        return .{
            .min = Vec3.init(@min(self.min.x, p.x), @min(self.min.y, p.y), @min(self.min.z, p.z)),
            .max = Vec3.init(@max(self.max.x, p.x), @max(self.max.y, p.y), @max(self.max.z, p.z)),
        };
    }

    pub fn centroid(self: AABB) Vec3 {
        return Vec3.scale(Vec3.add(self.min, self.max), 0.5);
    }

    pub fn surfaceArea(self: AABB) f32 {
        const d = Vec3.sub(self.max, self.min);
        return 2.0 * (d.x * d.y + d.y * d.z + d.z * d.x);
    }

    // Slab method; returns false if no intersection in [t_min, t_max].
    pub fn intersect(self: AABB, ray: Ray) bool {
        var t_min = ray.t_min;
        var t_max = ray.t_max;

        inline for ([_]usize{ 0, 1, 2 }) |axis| {
            const dir_comp = switch (axis) {
                0 => ray.direction.x,
                1 => ray.direction.y,
                2 => ray.direction.z,
                else => unreachable,
            };
            const orig_comp = switch (axis) {
                0 => ray.origin.x,
                1 => ray.origin.y,
                2 => ray.origin.z,
                else => unreachable,
            };
            const mn = switch (axis) {
                0 => self.min.x,
                1 => self.min.y,
                2 => self.min.z,
                else => unreachable,
            };
            const mx = switch (axis) {
                0 => self.max.x,
                1 => self.max.y,
                2 => self.max.z,
                else => unreachable,
            };
            const inv = 1.0 / dir_comp;
            var t0 = (mn - orig_comp) * inv;
            var t1 = (mx - orig_comp) * inv;
            if (inv < 0.0) std.mem.swap(f32, &t0, &t1);
            t_min = @max(t_min, t0);
            t_max = @min(t_max, t1);
            if (t_max < t_min) return false;
        }
        return true;
    }

    // Longest axis index (0=x, 1=y, 2=z).
    pub fn longestAxis(self: AABB) usize {
        const d = Vec3.sub(self.max, self.min);
        if (d.x >= d.y and d.x >= d.z) return 0;
        if (d.y >= d.z) return 1;
        return 2;
    }
};
