const math = @import("math");
const Spectrum = math.Spectrum;
const Ray = math.Ray;
const Vec3 = math.Vec3;
const Scene = @import("scene").Scene;
const sampler_mod = @import("sampler");
const Sampler = sampler_mod.Sampler;
const PathRecord = @import("integrator.zig").PathRecord;

pub const DirectLighting = struct {
    pub fn li(
        self: DirectLighting,
        ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        alloc: anytype,
    ) Spectrum {
        _ = self;
        _ = alloc;
        const hit = scene.intersect(ray) orelse return scene.background;
        const material = scene.materials[hit.material_index];
        var result = material.emission();
        const wo = Vec3.neg(ray.direction);

        for (scene.lights) |light| {
            const ls = light.sampleLi(hit.point, sampler.next2d()) orelse continue;
            if (ls.pdf < 1e-7) continue;
            const shadow_ray = Ray.init(hit.point, ls.wi);
            if (scene.intersectAny(shadow_ray, ls.dist - 1e-3)) continue;
            const f = material.eval(wo, ls.wi, hit);
            const cos_theta = @abs(Vec3.dot(ls.wi, hit.shading_normal));
            result = Spectrum.add(result, Spectrum.scale(Spectrum.mul(f, ls.li), cos_theta / ls.pdf));
        }
        return result;
    }

    pub fn liRecord(self: DirectLighting, ray: Ray, scene: *const Scene, sampler: *Sampler, alloc: anytype, record: *PathRecord) Spectrum {
        _ = record;
        return self.li(ray, scene, sampler, alloc);
    }
};
