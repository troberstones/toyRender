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
    world_bbox: AABB,
    // True when both transforms are the identity — lets us skip all matrix work.
    is_identity: bool,

    pub fn init(geo: Geometry, object_to_world: Mat4, world_to_object: Mat4, material_index: u32) Instance {
        var self = Instance{
            .geometry = geo,
            .object_to_world = object_to_world,
            .world_to_object = world_to_object,
            .material_index = material_index,
            .world_bbox = undefined,
            .is_identity = Mat4.isIdentity(object_to_world),
        };
        self.world_bbox = self.bbox();
        return self;
    }

    pub fn intersect(self: *const Instance, ray: Ray, t_min: f32, t_max: f32, out: *HitRecord) bool {
        if (!self.world_bbox.intersect(ray, t_min, t_max)) return false;

        // Identity transform: object space == world space, no matrix work needed.
        if (self.is_identity) {
            if (!self.geometry.intersect(ray, t_min, t_max, out)) return false;
            out.material_index = self.material_index;
            return true;
        }

        const o_ray = Ray{
            .origin = Mat4.transformPoint(self.world_to_object, ray.origin),
            .direction = Mat4.transformDirection(self.world_to_object, ray.direction),
            // inv_dir left default: no geometry consumes the object-space reciprocal.
            .t_min = t_min,
            .t_max = t_max,
        };

        // Geometry writes to *out directly; we then transform the world-space
        // fields in place — no intermediate HitRecord copy.
        if (!self.geometry.intersect(o_ray, t_min, t_max, out)) return false;
        out.point = Mat4.transformPoint(self.object_to_world, out.point);
        out.normal = Mat4.transformNormal(self.world_to_object, out.normal);
        out.shading_normal = Mat4.transformNormal(self.world_to_object, out.shading_normal);
        out.material_index = self.material_index;
        return true;
    }

    // Fast t-only test for shadow rays — skips normal/UV/transform-back.
    pub fn intersectT(self: *const Instance, ray: Ray, t_min: f32, t_max: f32) ?f32 {
        if (!self.world_bbox.intersect(ray, t_min, t_max)) return null;

        if (self.is_identity) {
            return self.geometry.intersectT(ray, t_min, t_max);
        }

        const o_ray = Ray{
            .origin = Mat4.transformPoint(self.world_to_object, ray.origin),
            .direction = Mat4.transformDirection(self.world_to_object, ray.direction),
            .t_min = t_min,
            .t_max = t_max,
        };
        return self.geometry.intersectT(o_ray, t_min, t_max);
    }

    pub fn bbox(self: Instance) AABB {
        const local = self.geometry.bbox();
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
