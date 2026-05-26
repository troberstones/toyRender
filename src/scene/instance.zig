const math = @import("math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Ray = math.Ray;
const AABB = math.AABB;
const geometry = @import("geometry");
const Geometry = geometry.Geometry;
const HitRecord = geometry.HitRecord;
const SurfaceSample = geometry.SurfaceSample;

pub const Instance = struct {
    geometry: Geometry,
    object_to_world: Mat4,
    world_to_object: Mat4,
    material_index: u32,

    pub fn intersect(self: *const Instance, ray: Ray, t_min: f32, t_max: f32) ?HitRecord {
        // Transform ray into object space.
        const o_ray = Ray{
            .origin = Mat4.transformPoint(self.world_to_object, ray.origin),
            .direction = Mat4.transformDirection(self.world_to_object, ray.direction),
            .t_min = t_min,
            .t_max = t_max,
        };

        var hit = self.geometry.intersect(o_ray, t_min, t_max) orelse return null;

        // Transform result back to world space.
        hit.point = Mat4.transformPoint(self.object_to_world, hit.point);
        hit.normal = Mat4.transformNormal(self.world_to_object, hit.normal);
        hit.shading_normal = Mat4.transformNormal(self.world_to_object, hit.shading_normal);
        hit.material_index = self.material_index;
        return hit;
    }

    pub fn bbox(self: Instance) AABB {
        const local = self.geometry.bbox();
        // Transform all 8 corners and compute world-space AABB.
        const corners = [8]Vec3{
            Vec3.init(local.min.x, local.min.y, local.min.z),
            Vec3.init(local.max.x, local.min.y, local.min.z),
            Vec3.init(local.min.x, local.max.y, local.min.z),
            Vec3.init(local.max.x, local.max.y, local.min.z),
            Vec3.init(local.min.x, local.min.y, local.max.z),
            Vec3.init(local.max.x, local.min.y, local.max.z),
            Vec3.init(local.min.x, local.max.y, local.max.z),
            Vec3.init(local.max.x, local.max.y, local.max.z),
        };
        var world = AABB.empty();
        for (corners) |c| {
            world = world.expandPoint(Mat4.transformPoint(self.object_to_world, c));
        }
        return world;
    }
};
