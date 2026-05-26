const Vec3 = @import("vec3.zig").Vec3;

pub const Ray = struct {
    origin: Vec3,
    direction: Vec3, // must be normalized
    t_min: f32 = 1e-4,
    t_max: f32 = std.math.floatMax(f32),

    const std = @import("std");

    pub fn init(origin: Vec3, direction: Vec3) Ray {
        return .{ .origin = origin, .direction = Vec3.normalize(direction) };
    }

    pub fn at(self: Ray, t: f32) Vec3 {
        return Vec3.add(self.origin, Vec3.scale(self.direction, t));
    }
};
