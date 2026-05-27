const math = @import("math");
const Vec3 = math.Vec3;
const Ray = math.Ray;
const AABB = math.AABB;

const TriangleMesh = @import("triangle_mesh.zig").TriangleMesh;
const Sphere = @import("analytic.zig").Sphere;
const Plane = @import("analytic.zig").Plane;

pub const HitRecord = struct {
    t: f32,
    point: Vec3,
    // Geometric normal (always faces against the ray).
    normal: Vec3,
    // Shading normal (from vertex interpolation or normal maps).
    shading_normal: Vec3,
    uv: [2]f32,
    material_index: u32,
    // True when ray hit the front face (ray and geometric normal oppose each other).
    front_face: bool,
};

pub const SurfaceSample = struct {
    point: Vec3,
    normal: Vec3,
    uv: [2]f32,
    pdf: f32, // w.r.t. surface area
};

// Tagged-union interface. Each variant must implement:
//   fn intersect(self, ray: Ray, t_min: f32, t_max: f32) ?HitRecord
//   fn bbox(self) AABB
//   fn sampleSurface(self, rng: [2]f32) SurfaceSample
//   fn area(self) f32
pub const Geometry = union(enum) {
    triangle_mesh: TriangleMesh,
    sphere: Sphere,
    plane: Plane,

    pub fn intersect(self: Geometry, ray: Ray, t_min: f32, t_max: f32) ?HitRecord {
        return switch (self) {
            inline else => |g| g.intersect(ray, t_min, t_max),
        };
    }

    pub fn intersectT(self: Geometry, ray: Ray, t_min: f32, t_max: f32) ?f32 {
        return switch (self) {
            inline else => |g| g.intersectT(ray, t_min, t_max),
        };
    }

    pub fn bbox(self: Geometry) AABB {
        return switch (self) {
            inline else => |g| g.bbox(),
        };
    }

    pub fn sampleSurface(self: Geometry, rng: [2]f32) SurfaceSample {
        return switch (self) {
            inline else => |g| g.sampleSurface(rng),
        };
    }

    pub fn area(self: Geometry) f32 {
        return switch (self) {
            inline else => |g| g.area(),
        };
    }
};
