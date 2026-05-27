const Vec3 = @import("vec3.zig").Vec3;

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3, // must be normalized
    inv_dir: Vec3,   // 1/direction, precomputed for AABB slab tests
    t_min: f32 = 1e-4,
    t_max: f32 = std.math.floatMax(f32),

    const std = @import("std");

    pub fn init(origin: Vec3, direction: Vec3) Ray {
        const d = Vec3.normalize(direction);
        return .{
            .origin = origin,
            .direction = d,
            .inv_dir = Vec3.init(1.0 / d.x, 1.0 / d.y, 1.0 / d.z),
        };
    }

    pub fn at(self: Ray, t: f32) Vec3 {
        return Vec3.add(self.origin, Vec3.scale(self.direction, t));
    }
};
