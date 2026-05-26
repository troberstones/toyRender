const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Ray = math.Ray;
const AABB = math.AABB;
const HitRecord = @import("geometry.zig").HitRecord;
const SurfaceSample = @import("geometry.zig").SurfaceSample;

pub const Sphere = struct {
    center: Vec3,
    radius: f32,
    material_index: u32,

    pub fn intersect(self: Sphere, ray: Ray, t_min: f32, t_max: f32) ?HitRecord {
        const oc = Vec3.sub(ray.origin, self.center);
        const a = Vec3.lengthSq(ray.direction);
        const half_b = Vec3.dot(oc, ray.direction);
        const c = Vec3.lengthSq(oc) - self.radius * self.radius;
        const discriminant = half_b * half_b - a * c;
        if (discriminant < 0) return null;

        const sqrt_d = @sqrt(discriminant);
        var root = (-half_b - sqrt_d) / a;
        if (root <= t_min or root >= t_max) {
            root = (-half_b + sqrt_d) / a;
            if (root <= t_min or root >= t_max) return null;
        }

        const point = ray.at(root);
        const outward_normal = Vec3.scale(Vec3.sub(point, self.center), 1.0 / self.radius);
        const front_face = Vec3.dot(ray.direction, outward_normal) < 0;
        const normal = if (front_face) outward_normal else Vec3.neg(outward_normal);

        // Spherical UV (longitude/latitude)
        const theta = std.math.acos(-outward_normal.y);
        const phi = std.math.atan2(-outward_normal.z, outward_normal.x) + std.math.pi;

        return HitRecord{
            .t = root,
            .point = point,
            .normal = normal,
            .shading_normal = normal,
            .uv = .{ phi / (2.0 * std.math.pi), theta / std.math.pi },
            .material_index = self.material_index,
            .front_face = front_face,
        };
    }

    pub fn bbox(self: Sphere) AABB {
        const r = Vec3.splat(self.radius);
        return .{
            .min = Vec3.sub(self.center, r),
            .max = Vec3.add(self.center, r),
        };
    }

    pub fn sampleSurface(self: Sphere, rng: [2]f32) SurfaceSample {
        // Uniform sampling on sphere surface
        const z = 1.0 - 2.0 * rng[0];
        const r = @sqrt(@max(0.0, 1.0 - z * z));
        const phi = 2.0 * std.math.pi * rng[1];
        const local = Vec3.init(r * @cos(phi), r * @sin(phi), z);
        const point = Vec3.add(self.center, Vec3.scale(local, self.radius));
        return .{
            .point = point,
            .normal = local,
            .uv = .{ rng[0], rng[1] },
            .pdf = 1.0 / self.area(),
        };
    }

    pub fn area(self: Sphere) f32 {
        return 4.0 * std.math.pi * self.radius * self.radius;
    }
};

pub const Plane = struct {
    // Defined by point on plane and outward normal.
    point: Vec3,
    normal: Vec3,
    // Half-extents for a finite plane (infinite if null).
    half_extents: ?[2]f32,
    material_index: u32,

    pub fn intersect(self: Plane, ray: Ray, t_min: f32, t_max: f32) ?HitRecord {
        const denom = Vec3.dot(self.normal, ray.direction);
        if (@abs(denom) < 1e-8) return null;
        const t = Vec3.dot(Vec3.sub(self.point, ray.origin), self.normal) / denom;
        if (t < t_min or t > t_max) return null;

        if (self.half_extents) |ext| {
            const hit_p = ray.at(t);
            const diff = Vec3.sub(hit_p, self.point);
            // Build a local 2D frame and check bounds — TODO: proper tangent frame
            _ = ext;
            _ = diff;
        }

        const front_face = Vec3.dot(ray.direction, self.normal) < 0;
        const n = if (front_face) self.normal else Vec3.neg(self.normal);
        return HitRecord{
            .t = t,
            .point = ray.at(t),
            .normal = n,
            .shading_normal = n,
            .uv = .{ 0, 0 }, // TODO: compute planar UV
            .material_index = self.material_index,
            .front_face = front_face,
        };
    }

    pub fn bbox(self: Plane) AABB {
        // Infinite plane has an infinite bbox; finite plane is a thin slab.
        if (self.half_extents) |ext| {
            // TODO: proper AABB for finite plane with arbitrary normal
            _ = ext;
        }
        // Degenerate — use a very large box for now
        return AABB.fromPoints(Vec3.splat(-1e10), Vec3.splat(1e10));
    }

    pub fn sampleSurface(self: Plane, rng: [2]f32) SurfaceSample {
        // TODO: uniform sampling over finite extent
        _ = rng;
        return .{
            .point = self.point,
            .normal = self.normal,
            .uv = .{ 0, 0 },
            .pdf = 0,
        };
    }

    pub fn area(self: Plane) f32 {
        if (self.half_extents) |ext| {
            return 4.0 * ext[0] * ext[1];
        }
        return std.math.floatMax(f32);
    }
};
