const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const Ray = math.Ray;
const LightSample = @import("light.zig").LightSample;

pub const PointLight = struct {
    position: Vec3,
    intensity: Spectrum, // radiant intensity (W/sr)

    pub fn sampleLi(self: PointLight, hit_point: Vec3, rng: [2]f32) ?LightSample {
        _ = rng;
        const to_light = Vec3.sub(self.position, hit_point);
        const dist_sq = Vec3.lengthSq(to_light);
        const dist = @sqrt(dist_sq);
        const wi = Vec3.scale(to_light, 1.0 / dist);
        return LightSample{
            .li = Spectrum.scale(self.intensity, 1.0 / dist_sq),
            .wi = wi,
            .pdf = 1.0,
            .dist = dist,
        };
    }

    pub fn pdfLi(self: PointLight, hit_point: Vec3, wi: Vec3) f32 {
        _ = self;
        _ = hit_point;
        _ = wi;
        return 0.0; // delta distribution
    }

    pub fn le(self: PointLight, ray: Ray) Spectrum {
        _ = self;
        _ = ray;
        return Spectrum.zero();
    }

    pub fn isDelta(self: PointLight) bool {
        _ = self;
        return true;
    }
};
