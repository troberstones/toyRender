const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const Ray = math.Ray;
const scene_mod = @import("scene");
const Scene = scene_mod.Scene;
const sampler_mod = @import("sampler");
const Sampler = sampler_mod.Sampler;
const material_mod = @import("material");
const light_mod = @import("light");
const PathRecord = @import("integrator.zig").PathRecord;
const PathSegment = @import("integrator.zig").PathSegment;

pub const PathTracer = struct {
    max_depth: u32,
    rr_depth: u32, // depth at which Russian roulette starts

    pub fn li(
        self: PathTracer,
        ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        alloc: std.mem.Allocator,
    ) Spectrum {
        _ = alloc;
        return self.trace(ray, scene, sampler, null);
    }

    pub fn liRecord(
        self: PathTracer,
        ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        alloc: std.mem.Allocator,
        record: *PathRecord,
    ) Spectrum {
        _ = alloc;
        return self.trace(ray, scene, sampler, record);
    }

    fn trace(
        self: PathTracer,
        initial_ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        record: ?*PathRecord,
    ) Spectrum {
        var radiance = Spectrum.zero();
        var throughput = Spectrum.one();
        var ray = initial_ray;

        var depth: u32 = 0;
        while (depth <= self.max_depth) : (depth += 1) {
            const hit = scene.intersect(ray) orelse {
                // Miss — add background / environment light.
                for (scene.lights) |light| {
                    radiance = Spectrum.add(radiance, Spectrum.mul(throughput, light.le(ray)));
                }
                break;
            };

            const material = scene.materials[hit.material_index];

            // Emission from hit surface.
            const emit = material.emission();
            radiance = Spectrum.add(radiance, Spectrum.mul(throughput, emit));

            if (depth == self.max_depth) break;

            // Sample direct lighting (MIS with light and BSDF sampling).
            const wo = Vec3.neg(ray.direction);
            radiance = Spectrum.add(radiance, Spectrum.mul(throughput, sampleDirectLighting(scene, wo, hit, sampler)));

            // Sample BSDF for the next ray direction.
            const bsdf_sample = material.sample(wo, hit, sampler.next2d()) orelse break;
            if (bsdf_sample.pdf < 1e-7) break;

            // Record segment for path visualization.
            if (record) |rec| {
                rec.segments.append(rec.alloc, .{
                    .origin = hit.point,
                    .direction = bsdf_sample.wi,
                    .length = 0, // filled in on next hit
                    .lobe = bsdf_sample.lobe,
                    .depth = @intCast(depth),
                    .throughput = throughput,
                }) catch {};
            }

            const cos_theta = @abs(Vec3.dot(bsdf_sample.wi, hit.shading_normal));
            const weight = Spectrum.scale(bsdf_sample.f, cos_theta / bsdf_sample.pdf);
            throughput = Spectrum.mul(throughput, weight);

            // Russian roulette.
            if (depth >= self.rr_depth) {
                const q = @max(0.05, 1.0 - throughput.luminance());
                if (sampler.next1d() < q) break;
                throughput = Spectrum.scale(throughput, 1.0 / (1.0 - q));
            }

            ray = Ray.init(hit.point, bsdf_sample.wi);
        }

        return radiance;
    }

    fn sampleDirectLighting(
        scene: *const Scene,
        wo: Vec3,
        hit: anytype,
        sampler: *Sampler,
    ) Spectrum {
        if (scene.lights.len == 0) return Spectrum.zero();

        // Uniform light selection.
        const light_idx = @as(usize, @intFromFloat(
            sampler.next1d() * @as(f32, @floatFromInt(scene.lights.len)),
        )) % scene.lights.len;
        const light = scene.lights[light_idx];
        const light_count = @as(f32, @floatFromInt(scene.lights.len));

        const ls = light.sampleLi(hit.point, sampler.next2d()) orelse return Spectrum.zero();
        if (ls.pdf < 1e-7 or ls.li.isBlack()) return Spectrum.zero();

        // Shadow ray.
        const shadow_ray = Ray.init(hit.point, ls.wi);
        if (scene.intersectAny(shadow_ray, ls.dist - 1e-3)) return Spectrum.zero();

        const mat = scene.materials[hit.material_index];
        const f = mat.eval(wo, ls.wi, hit);
        const cos_theta = @abs(Vec3.dot(ls.wi, hit.shading_normal));

        // MIS: balance heuristic between light and BSDF sampling.
        // Skip MIS for delta lights.
        const mis_weight: f32 = if (light.isDelta()) 1.0 else blk: {
            const bsdf_pdf = mat.pdf(wo, ls.wi, hit);
            break :blk powerHeuristic(ls.pdf, bsdf_pdf);
        };

        return Spectrum.scale(
            Spectrum.mul(f, ls.li),
            mis_weight * cos_theta / (ls.pdf * light_count),
        );
    }

    fn powerHeuristic(pdf_a: f32, pdf_b: f32) f32 {
        const a2 = pdf_a * pdf_a;
        const b2 = pdf_b * pdf_b;
        return a2 / (a2 + b2);
    }
};
