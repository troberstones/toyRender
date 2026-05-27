const std = @import("std");
const math = @import("math");
const Ray = math.Ray;
const perf = @import("perf");
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
        perf.global.addRay();
        var best: HitRecord = undefined;
        var found = false;
        var closest = ray.t_max;
        for (self.instances) |*inst| {
            // Instance writes directly into best; shrinking closest lets the
            // bbox pre-cull reject instances behind the current best hit.
            if (inst.intersect(ray, ray.t_min, closest, &best)) {
                closest = best.t;
                found = true;
            }
        }
        return if (found) best else null;
    }

    pub fn intersectAny(self: *const Scene, ray: Ray, max_t: f32) bool {
        perf.global.addShadowRay();
        for (self.instances) |*inst| {
            if (inst.intersectT(ray, ray.t_min, max_t) != null) return true;
        }
        return false;
    }

    pub fn deinit(self: *Scene) void {
        self.alloc.free(self.instances);
        self.alloc.free(self.materials);
        self.alloc.free(self.lights);
    }
};
