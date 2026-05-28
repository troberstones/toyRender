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
        perf.thread_rays += 1;
        return self.accel.intersect(ray);
    }

    pub fn intersectAny(self: *const Scene, ray: Ray, max_t: f32) bool {
        perf.thread_shadow_rays += 1;
        return self.accel.intersectAny(ray, max_t);
    }

    pub fn deinit(self: *Scene) void {
        self.accel.deinit(self.alloc);
        for (self.instances) |inst| {
            switch (inst.geometry) {
                .triangle_mesh => |mesh| {
                    self.alloc.free(@constCast(mesh.vertices));
                    self.alloc.free(@constCast(mesh.triangles));
                },
                else => {},
            }
        }
        self.alloc.free(self.instances);
        self.alloc.free(self.materials);
        self.alloc.free(self.lights);
    }
};
