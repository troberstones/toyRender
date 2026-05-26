const std = @import("std");
const math = @import("math");
const Ray = math.Ray;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const accel = @import("accel");
const AccelStructure = accel.AccelStructure;
const material_mod = @import("material");
const Material = material_mod.Material;
const light_mod = @import("light");
const Light = light_mod.Light;
const Instance = @import("instance.zig").Instance;
const Camera = @import("camera.zig").Camera;

pub const Scene = struct {
    camera: Camera,
    instances: []Instance,
    materials: []Material,
    lights: []Light,
    accel: AccelStructure,
    background: Spectrum,
    alloc: std.mem.Allocator,

    pub fn intersect(self: *const Scene, ray: Ray) ?HitRecord {
        // TODO: route through accel structure
        // For now, brute-force over instances
        var closest = ray.t_max;
        var best: ?HitRecord = null;
        for (self.instances) |*inst| {
            if (inst.intersect(ray, ray.t_min, closest)) |hit| {
                closest = hit.t;
                best = hit;
            }
        }
        return best;
    }

    pub fn intersectAny(self: *const Scene, ray: Ray, max_t: f32) bool {
        for (self.instances) |*inst| {
            if (inst.intersect(ray, ray.t_min, max_t) != null) return true;
        }
        return false;
    }

    pub fn deinit(self: *Scene) void {
        self.alloc.free(self.instances);
        self.alloc.free(self.materials);
        self.alloc.free(self.lights);
    }
};
