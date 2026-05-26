const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const BxdfSample = @import("material.zig").BxdfSample;

pub const Lambertian = struct {
    albedo: Spectrum,

    pub fn eval(self: Lambertian, wo: Vec3, wi: Vec3, hit: HitRecord) Spectrum {
        _ = wo;
        const cos_theta = Vec3.dot(wi, hit.shading_normal);
        if (cos_theta <= 0) return Spectrum.zero();
        return Spectrum.scale(self.albedo, 1.0 / std.math.pi);
    }

    pub fn sample(self: Lambertian, wo: Vec3, hit: HitRecord, rng: [2]f32) ?BxdfSample {
        _ = wo;
        // Cosine-weighted hemisphere sampling
        const wi_local = cosineSampleHemisphere(rng);
        const wi = Vec3.toWorld(wi_local, hit.shading_normal);
        const cos_theta = wi_local.z;
        if (cos_theta <= 0) return null;
        return BxdfSample{
            .wi = wi,
            .f = Spectrum.scale(self.albedo, 1.0 / std.math.pi),
            .pdf = cos_theta / std.math.pi,
            .lobe = .diffuse,
            .is_specular = false,
        };
    }

    pub fn pdf(self: Lambertian, wo: Vec3, wi: Vec3, hit: HitRecord) f32 {
        _ = self;
        _ = wo;
        const cos_theta = @max(Vec3.dot(wi, hit.shading_normal), 0.0);
        return cos_theta / std.math.pi;
    }

    pub fn emission(self: Lambertian) Spectrum {
        _ = self;
        return Spectrum.zero();
    }

    fn cosineSampleHemisphere(rng: [2]f32) Vec3 {
        const r = @sqrt(rng[0]);
        const phi = 2.0 * std.math.pi * rng[1];
        return Vec3.init(r * @cos(phi), r * @sin(phi), @sqrt(@max(0.0, 1.0 - rng[0])));
    }
};
