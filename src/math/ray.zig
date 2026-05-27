const Vec3 = @import("vec3.zig").Vec3;

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3, // must be normalized
    // 1/direction, precomputed for AABB slab tests. Only valid for rays built
    // via init/initNormalized; defaults to undefined so callers that never run
    // an AABB test (e.g. object-space rays) can skip the 3 divisions.
    inv_dir: Vec3 = undefined,
    t_min: f32 = 1e-4,
    t_max: f32 = std.math.floatMax(f32),

    const std = @import("std");

    pub fn init(origin: Vec3, direction: Vec3) Ray {
        return initNormalized(origin, Vec3.normalize(direction));
    }

    /// Like init but assumes `direction` is already unit length — skips the normalize.
    pub fn initNormalized(origin: Vec3, direction: Vec3) Ray {
        return .{
            .origin = origin,
            .direction = direction,
            .inv_dir = Vec3.init(1.0 / direction.x, 1.0 / direction.y, 1.0 / direction.z),
        };
    }

    pub fn at(self: Ray, t: f32) Vec3 {
        return Vec3.add(self.origin, Vec3.scale(self.direction, t));
    }
};
