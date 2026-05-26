const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const BxdfSample = @import("material.zig").BxdfSample;

pub const Ggx = struct {
    base_color: Spectrum,
    roughness: f32, // alpha = roughness^2
    metallic: f32,

    pub fn eval(self: Ggx, wo: Vec3, wi: Vec3, hit: HitRecord) Spectrum {
        const n = hit.shading_normal;
        const cos_o = Vec3.dot(wo, n);
        const cos_i = Vec3.dot(wi, n);
        if (cos_o <= 0 or cos_i <= 0) return Spectrum.zero();

        const h = Vec3.normalize(Vec3.add(wo, wi));
        const alpha = self.roughness * self.roughness;

        const d = ggxD(n, h, alpha);
        const g = smithG1(n, wo, alpha) * smithG1(n, wi, alpha);
        const f = fresnelSchlick(self.fresnelF0(), Vec3.dot(wo, h));

        const denom = 4.0 * cos_o * cos_i;
        if (denom < 1e-7) return Spectrum.zero();
        return Spectrum.scale(Spectrum.mul(f, Spectrum.splat(d * g / denom)), 1.0);
    }

    pub fn sample(self: Ggx, wo: Vec3, hit: HitRecord, rng: [2]f32) ?BxdfSample {
        const n = hit.shading_normal;
        const alpha = self.roughness * self.roughness;
        const h_local = sampleGgxVndf(rng, alpha);
        const h = Vec3.toWorld(h_local, n);
        const wi = Vec3.reflect(Vec3.neg(wo), h);

        if (Vec3.dot(wi, n) <= 0) return null;

        const f = self.eval(wo, wi, hit);
        const p = self.pdf(wo, wi, hit);
        if (p < 1e-7) return null;

        return BxdfSample{
            .wi = wi,
            .f = f,
            .pdf = p,
            .lobe = .glossy_reflection,
            .is_specular = false,
        };
    }

    pub fn pdf(self: Ggx, wo: Vec3, wi: Vec3, hit: HitRecord) f32 {
        const n = hit.shading_normal;
        if (Vec3.dot(wo, n) <= 0 or Vec3.dot(wi, n) <= 0) return 0;
        const h = Vec3.normalize(Vec3.add(wo, wi));
        const alpha = self.roughness * self.roughness;
        const d = ggxD(n, h, alpha);
        return d * @abs(Vec3.dot(n, h)) / (4.0 * @abs(Vec3.dot(wo, h)));
    }

    pub fn emission(self: Ggx) Spectrum {
        _ = self;
        return Spectrum.zero();
    }

    fn fresnelF0(self: Ggx) Spectrum {
        const dielectric_f0 = Spectrum.splat(0.04);
        return Spectrum.lerp(dielectric_f0, self.base_color, self.metallic);
    }

    fn fresnelSchlick(f0: Spectrum, cos_theta: f32) Spectrum {
        const t = std.math.pow(f32, 1.0 - @max(cos_theta, 0.0), 5.0);
        const one_minus_f0 = Spectrum.init(1.0 - f0.r, 1.0 - f0.g, 1.0 - f0.b);
        return Spectrum.add(f0, Spectrum.scale(one_minus_f0, t));
    }

    fn ggxD(n: Vec3, h: Vec3, alpha: f32) f32 {
        const cos_h = Vec3.dot(n, h);
        if (cos_h <= 0) return 0;
        const a2 = alpha * alpha;
        const denom = cos_h * cos_h * (a2 - 1.0) + 1.0;
        return a2 / (std.math.pi * denom * denom);
    }

    fn smithG1(n: Vec3, v: Vec3, alpha: f32) f32 {
        const cos_v = @abs(Vec3.dot(n, v));
        const a2 = alpha * alpha;
        const denom = cos_v + @sqrt(a2 + (1.0 - a2) * cos_v * cos_v);
        if (denom < 1e-7) return 0;
        return 2.0 * cos_v / denom;
    }

    fn sampleGgxVndf(rng: [2]f32, alpha: f32) Vec3 {
        // TODO: proper VNDF sampling (Heitz 2018) for reduced variance
        const phi = 2.0 * std.math.pi * rng[0];
        const cos_theta_sq = (1.0 - rng[1]) / (1.0 + (alpha * alpha - 1.0) * rng[1]);
        const cos_theta = @sqrt(@max(0.0, cos_theta_sq));
        const sin_theta = @sqrt(@max(0.0, 1.0 - cos_theta_sq));
        return Vec3.init(sin_theta * @cos(phi), sin_theta * @sin(phi), cos_theta);
    }
};

