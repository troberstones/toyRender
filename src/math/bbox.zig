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

/// SoA layout holding 4 AABBs for 4-wide SIMD ray intersection tests.
/// Maps to ARM NEON on M4 via Zig's @Vector(4, f32).
pub const AabbPack = struct {
    min_x: @Vector(4, f32),
    min_y: @Vector(4, f32),
    min_z: @Vector(4, f32),
    max_x: @Vector(4, f32),
    max_y: @Vector(4, f32),
    max_z: @Vector(4, f32),

    /// Build from exactly 4 AABBs. To pack fewer than 4, pass AABB.empty()
    /// for unused slots — the slab test will always return a miss for those lanes.
    pub fn init(aabbs: [4]AABB) AabbPack {
        return .{
            .min_x = .{ aabbs[0].min.x, aabbs[1].min.x, aabbs[2].min.x, aabbs[3].min.x },
            .min_y = .{ aabbs[0].min.y, aabbs[1].min.y, aabbs[2].min.y, aabbs[3].min.y },
            .min_z = .{ aabbs[0].min.z, aabbs[1].min.z, aabbs[2].min.z, aabbs[3].min.z },
            .max_x = .{ aabbs[0].max.x, aabbs[1].max.x, aabbs[2].max.x, aabbs[3].max.x },
            .max_y = .{ aabbs[0].max.y, aabbs[1].max.y, aabbs[2].max.y, aabbs[3].max.y },
            .max_z = .{ aabbs[0].max.z, aabbs[1].max.z, aabbs[2].max.z, aabbs[3].max.z },
        };
    }

    /// 4-wide ray-AABB slab test.
    /// Returns the entry t for each lane. A lane returns std.math.floatMax(f32)
    /// when the ray misses that AABB (t_enter > t_exit, t_exit < t_min, or
    /// t_enter > t_max).  All arithmetic uses @Vector(4, f32) so the compiler
    /// emits NEON fmin/fmax/fmul on AArch64.
    pub fn intersect4(self: AabbPack, ray: Ray, t_min: f32, t_max: f32) @Vector(4, f32) {
        const inf4: @Vector(4, f32) = @splat(std.math.floatMax(f32));

        // Broadcast scalar ray fields to 4-wide vectors.
        const ox: @Vector(4, f32) = @splat(ray.origin.x);
        const oy: @Vector(4, f32) = @splat(ray.origin.y);
        const oz: @Vector(4, f32) = @splat(ray.origin.z);
        const idx: @Vector(4, f32) = @splat(ray.inv_dir.x);
        const idy: @Vector(4, f32) = @splat(ray.inv_dir.y);
        const idz: @Vector(4, f32) = @splat(ray.inv_dir.z);
        const tmin4: @Vector(4, f32) = @splat(t_min);
        const tmax4: @Vector(4, f32) = @splat(t_max);

        // Per-axis slab distances.
        const tx0 = (self.min_x - ox) * idx;
        const tx1 = (self.max_x - ox) * idx;
        const ty0 = (self.min_y - oy) * idy;
        const ty1 = (self.max_y - oy) * idy;
        const tz0 = (self.min_z - oz) * idz;
        const tz1 = (self.max_z - oz) * idz;

        // t_enter = max over axes of the near slab; t_exit = min over axes of the far slab.
        const t_enter = @max(@min(tx0, tx1), @max(@min(ty0, ty1), @min(tz0, tz1)));
        const t_exit  = @min(@max(tx0, tx1), @min(@max(ty0, ty1), @max(tz0, tz1)));

        // Hit condition: max(t_enter, t_min) <= min(t_exit, t_max)
        const hit = @max(t_enter, tmin4) <= @min(t_exit, tmax4);

        // Return t_enter for hit lanes, floatMax for miss lanes.
        return @select(f32, hit, t_enter, inf4);
    }
};

test "AabbPack: ray hits all 4 lanes" {
    // Four unit cubes centered at x = 1, 3, 5, 7 along the x-axis.
    const boxes = [4]AABB{
        AABB.fromPoints(Vec3.init(0, -1, -1), Vec3.init(2,  1,  1)),
        AABB.fromPoints(Vec3.init(2, -1, -1), Vec3.init(4,  1,  1)),
        AABB.fromPoints(Vec3.init(4, -1, -1), Vec3.init(6,  1,  1)),
        AABB.fromPoints(Vec3.init(6, -1, -1), Vec3.init(8,  1,  1)),
    };
    const pack = AabbPack.init(boxes);
    const ray = Ray.init(Vec3.init(-1, 0, 0), Vec3.init(1, 0, 0));
    const result = pack.intersect4(ray, 0, std.math.floatMax(f32));

    const inf = std.math.floatMax(f32);
    // All lanes must be finite (not inf).
    try std.testing.expect(result[0] < inf);
    try std.testing.expect(result[1] < inf);
    try std.testing.expect(result[2] < inf);
    try std.testing.expect(result[3] < inf);
    // Entry t values must be monotonically increasing.
    try std.testing.expect(result[0] < result[1]);
    try std.testing.expect(result[1] < result[2]);
    try std.testing.expect(result[2] < result[3]);
}

test "AabbPack: ray misses some lanes" {
    // First two boxes straddle the ray; last two are off to the side.
    const boxes = [4]AABB{
        AABB.fromPoints(Vec3.init(0, -1, -1), Vec3.init(2,  1,  1)),
        AABB.fromPoints(Vec3.init(2, -1, -1), Vec3.init(4,  1,  1)),
        AABB.fromPoints(Vec3.init(0,  5,  5), Vec3.init(2,  7,  7)), // miss
        AABB.fromPoints(Vec3.init(2,  5,  5), Vec3.init(4,  7,  7)), // miss
    };
    const pack = AabbPack.init(boxes);
    const ray = Ray.init(Vec3.init(-1, 0, 0), Vec3.init(1, 0, 0));
    const result = pack.intersect4(ray, 0, std.math.floatMax(f32));

    const inf = std.math.floatMax(f32);
    try std.testing.expect(result[0] < inf);  // hit
    try std.testing.expect(result[1] < inf);  // hit
    try std.testing.expectEqual(inf, result[2]); // miss
    try std.testing.expectEqual(inf, result[3]); // miss
}

test "AabbPack: results match scalar AABB.intersect per lane" {
    const boxes = [4]AABB{
        AABB.fromPoints(Vec3.init(0, -1, -1), Vec3.init(2, 1, 1)),
        AABB.fromPoints(Vec3.init(3, -1, -1), Vec3.init(5, 1, 1)),
        AABB.fromPoints(Vec3.init(0,  5,  5), Vec3.init(2, 7, 7)), // miss
        AABB.empty(),                                                 // degenerate padding
    };
    const pack = AabbPack.init(boxes);
    const ray = Ray.init(Vec3.init(-1, 0, 0), Vec3.init(1, 0, 0));
    const t_min: f32 = 0;
    const t_max: f32 = std.math.floatMax(f32);
    const result = pack.intersect4(ray, t_min, t_max);

    const inf = std.math.floatMax(f32);
    for (0..4) |i| {
        const scalar_hit = boxes[i].intersect(ray, t_min, t_max);
        if (scalar_hit) {
            try std.testing.expect(result[i] < inf);
        } else {
            try std.testing.expectEqual(inf, result[i]);
        }
    }
}
