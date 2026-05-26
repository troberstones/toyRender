const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const Ray = math.Ray;
const geometry = @import("geometry");
const LightSample = @import("light.zig").LightSample;

pub const AreaLight = struct {
    // Index into scene.instances — the emissive surface.
    instance_index: u32,
    emission: Spectrum, // radiance (W/m²/sr)
    // Cached geometry reference for sampling (set during scene build).
    surface_area: f32,

    pub fn sampleLi(self: AreaLight, hit_point: Vec3, rng: [2]f32) ?LightSample {
        _ = self;
        _ = hit_point;
        _ = rng;
        // TODO: sample a point on the emissive surface, compute solid angle pdf
        return null;
    }

    pub fn pdfLi(self: AreaLight, hit_point: Vec3, wi: Vec3) f32 {
        _ = self;
        _ = hit_point;
        _ = wi;
        // TODO: convert area pdf to solid angle pdf
        return 0;
    }

    pub fn le(self: AreaLight, ray: Ray) Spectrum {
        // Emissive only from the front face.
        _ = ray;
        return self.emission;
    }

    pub fn isDelta(self: AreaLight) bool {
        _ = self;
        return false;
    }
};
