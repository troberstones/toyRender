const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const BxdfSample = @import("material.zig").BxdfSample;

pub const Dielectric = struct {
    ior: f32, // index of refraction (e.g. 1.5 for glass)
    tint: Spectrum,

    pub fn eval(self: Dielectric, wo: Vec3, wi: Vec3, hit: HitRecord) Spectrum {
        _ = self;
        _ = wo;
        _ = wi;
        _ = hit;
        return Spectrum.zero(); // delta distribution
    }

    pub fn sample(self: Dielectric, wo: Vec3, hit: HitRecord, rng: [2]f32) ?BxdfSample {
        const eta = if (hit.front_face) 1.0 / self.ior else self.ior;
        const n = hit.shading_normal;
        const cos_theta = @min(Vec3.dot(Vec3.neg(wo), n), 1.0);
        const reflectance = schlick(cos_theta, eta);

        if (rng[0] < reflectance) {
            // Reflect
            const wi = Vec3.reflect(Vec3.neg(wo), n);
            const cos_i = @abs(Vec3.dot(wi, n));
            if (cos_i < 1e-7) return null;
            return BxdfSample{
                .wi = wi,
                .f = Spectrum.scale(self.tint, 1.0 / cos_i),
                .pdf = reflectance,
                .lobe = .specular_reflection,
                .is_specular = true,
            };
        } else {
            // Refract
            const wi = Vec3.refract(Vec3.neg(wo), n, eta) orelse return null;
            const cos_i = @abs(Vec3.dot(wi, n));
            if (cos_i < 1e-7) return null;
            return BxdfSample{
                .wi = wi,
                .f = Spectrum.scale(self.tint, eta * eta / cos_i),
                .pdf = 1.0 - reflectance,
                .lobe = .specular_transmission,
                .is_specular = true,
            };
        }
    }

    pub fn pdf(self: Dielectric, wo: Vec3, wi: Vec3, hit: HitRecord) f32 {
        _ = self;
        _ = wo;
        _ = wi;
        _ = hit;
        return 0.0;
    }

    pub fn emission(self: Dielectric) Spectrum {
        _ = self;
        return Spectrum.zero();
    }

    fn schlick(cos_theta: f32, eta: f32) f32 {
        var r0 = (1.0 - eta) / (1.0 + eta);
        r0 = r0 * r0;
        const t = 1.0 - cos_theta;
        return r0 + (1.0 - r0) * t * t * t * t * t;
    }
};
