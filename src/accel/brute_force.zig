const math = @import("math");
const Ray = math.Ray;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const InstanceRef = @import("instance_ref.zig").InstanceRef;

pub const BruteForce = struct {
    instances: []const InstanceRef,

    pub fn intersect(self: *BruteForce, ray: Ray) ?HitRecord {
        var closest = ray.t_max;
        var best: ?HitRecord = null;
        for (self.instances) |inst| {
            if (inst.intersect(ray, ray.t_min, closest)) |hit| {
                closest = hit.t;
                best = hit;
            }
        }
        return best;
    }

    pub fn intersectAny(self: *BruteForce, ray: Ray, max_t: f32) bool {
        for (self.instances) |inst| {
            if (inst.intersect(ray, ray.t_min, max_t) != null) return true;
        }
        return false;
    }
};
