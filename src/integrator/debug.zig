const math = @import("math");
const Spectrum = math.Spectrum;
const Vec3 = math.Vec3;
const Ray = math.Ray;
const Scene = @import("scene").Scene;
const sampler_mod = @import("sampler");
const Sampler = sampler_mod.Sampler;
const PathRecord = @import("integrator.zig").PathRecord;

pub const DebugView = struct {
    pub const DebugMode = enum {
        normals,
        shading_normals,
        albedo,
        depth,
        uv,
        path_length,
    };

    mode: DebugMode,
    depth_scale: f32 = 5.0, // world units that map to white

    pub fn li(
        self: DebugView,
        ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        alloc: anytype,
    ) Spectrum {
        _ = sampler;
        _ = alloc;
        const hit = scene.intersect(ray) orelse return scene.background;

        return switch (self.mode) {
            .normals, .shading_normals => {
                const n = if (self.mode == .normals) hit.normal else hit.shading_normal;
                return Spectrum.init(
                    n.x * 0.5 + 0.5,
                    n.y * 0.5 + 0.5,
                    n.z * 0.5 + 0.5,
                );
            },
            .albedo => {
                const mat = scene.materials[hit.material_index];
                return mat.eval(Vec3.neg(ray.direction), hit.normal, hit);
            },
            .depth => {
                const d = @min(hit.t / self.depth_scale, 1.0);
                return Spectrum.splat(d);
            },
            .uv => Spectrum.init(hit.uv[0], hit.uv[1], 0),
            .path_length => Spectrum.splat(0), // N/A for direct debug view
        };
    }

    pub fn liRecord(self: DebugView, ray: Ray, scene: *const Scene, sampler: *Sampler, alloc: anytype, record: *PathRecord) Spectrum {
        _ = record;
        return self.li(ray, scene, sampler, alloc);
    }
};
