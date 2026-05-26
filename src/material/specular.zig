const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const BxdfSample = @import("material.zig").BxdfSample;

pub const Specular = struct {
    reflectance: Spectrum,

    pub fn eval(self: Specular, wo: Vec3, wi: Vec3, hit: HitRecord) Spectrum {
        _ = self;
        _ = wo;
        _ = wi;
        _ = hit;
        return Spectrum.zero(); // delta distribution
    }

    pub fn sample(self: Specular, wo: Vec3, hit: HitRecord, rng: [2]f32) ?BxdfSample {
        _ = rng;
        const n = hit.shading_normal;
        const wi = Vec3.reflect(Vec3.neg(wo), n);
        const cos_theta = @abs(Vec3.dot(wi, n));
        if (cos_theta < 1e-7) return null;
        return BxdfSample{
            .wi = wi,
            .f = Spectrum.scale(self.reflectance, 1.0 / cos_theta),
            .pdf = 1.0,
            .lobe = .specular_reflection,
            .is_specular = true,
        };
    }

    pub fn pdf(self: Specular, wo: Vec3, wi: Vec3, hit: HitRecord) f32 {
        _ = self;
        _ = wo;
        _ = wi;
        _ = hit;
        return 0.0; // delta distribution
    }

    pub fn emission(self: Specular) Spectrum {
        _ = self;
        return Spectrum.zero();
    }
};
