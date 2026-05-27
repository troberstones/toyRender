const math = @import("math");
const Ray = math.Ray;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const InstanceRef = @import("instance_ref.zig").InstanceRef;

pub const BruteForce = struct {
    instances: []const InstanceRef,

    pub fn intersect(self: *BruteForce, ray: Ray) ?HitRecord {
        var best: HitRecord = undefined;
        var found = false;
        var closest = ray.t_max;
        for (self.instances) |inst| {
            if (!inst.bbox.intersect(ray, ray.t_min, closest)) continue;
            if (inst.intersect(ray, ray.t_min, closest, &best)) {
                closest = best.t;
                found = true;
            }
        }
        return if (found) best else null;
    }

    pub fn intersectAny(self: *BruteForce, ray: Ray, max_t: f32) bool {
        for (self.instances) |inst| {
            if (!inst.bbox.intersect(ray, ray.t_min, max_t)) continue;
            if (inst.intersectT(ray, ray.t_min, max_t) != null) return true;
        }
        return false;
    }
};
