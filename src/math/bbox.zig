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

    // Slab method using precomputed inv_dir; returns false if no intersection in [t_min, t_max].
    // @min/@max handle negative inv_dir without a branch (IEEE 754 safe).
    pub fn intersect(self: AABB, ray: Ray, t_min: f32, t_max: f32) bool {
        const tx0 = (self.min.x - ray.origin.x) * ray.inv_dir.x;
        const tx1 = (self.max.x - ray.origin.x) * ray.inv_dir.x;
        const ty0 = (self.min.y - ray.origin.y) * ray.inv_dir.y;
        const ty1 = (self.max.y - ray.origin.y) * ray.inv_dir.y;
        const tz0 = (self.min.z - ray.origin.z) * ray.inv_dir.z;
        const tz1 = (self.max.z - ray.origin.z) * ray.inv_dir.z;
        const t_enter = @max(@min(tx0, tx1), @max(@min(ty0, ty1), @min(tz0, tz1)));
        const t_exit  = @min(@max(tx0, tx1), @min(@max(ty0, ty1), @max(tz0, tz1)));
        return @max(t_enter, t_min) <= @min(t_exit, t_max);
    }

    // Longest axis index (0=x, 1=y, 2=z).
    pub fn longestAxis(self: AABB) usize {
        const d = Vec3.sub(self.max, self.min);
        if (d.x >= d.y and d.x >= d.z) return 0;
        if (d.y >= d.z) return 1;
        return 2;
    }
};
