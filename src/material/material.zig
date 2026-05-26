const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;

const Lambertian = @import("lambertian.zig").Lambertian;
const Specular = @import("specular.zig").Specular;
const Ggx = @import("ggx.zig").Ggx;
const Dielectric = @import("dielectric.zig").Dielectric;

pub const BxdfLobe = enum {
    diffuse,
    specular_reflection,
    specular_transmission,
    glossy_reflection,
    glossy_transmission,
};

pub const BxdfSample = struct {
    wi: Vec3,
    f: Spectrum,     // BxDF value f(wo, wi)
    pdf: f32,
    lobe: BxdfLobe,
    is_specular: bool, // delta distribution — skip MIS weight
};

// Tagged-union BxDF interface. Each variant must implement:
//   fn eval(self, wo: Vec3, wi: Vec3, hit: HitRecord) Spectrum
//   fn sample(self, wo: Vec3, hit: HitRecord, rng: [2]f32) ?BxdfSample
//   fn pdf(self, wo: Vec3, wi: Vec3, hit: HitRecord) f32
//   fn emission(self) Spectrum   (zero for non-emissive)
pub const Material = union(enum) {
    lambertian: Lambertian,
    specular: Specular,
    ggx: Ggx,
    dielectric: Dielectric,

    pub fn eval(self: Material, wo: Vec3, wi: Vec3, hit: HitRecord) Spectrum {
        return switch (self) {
            inline else => |m| m.eval(wo, wi, hit),
        };
    }

    pub fn sample(self: Material, wo: Vec3, hit: HitRecord, rng: [2]f32) ?BxdfSample {
        return switch (self) {
            inline else => |m| m.sample(wo, hit, rng),
        };
    }

    pub fn pdf(self: Material, wo: Vec3, wi: Vec3, hit: HitRecord) f32 {
        return switch (self) {
            inline else => |m| m.pdf(wo, wi, hit),
        };
    }

    pub fn emission(self: Material) Spectrum {
        return switch (self) {
            inline else => |m| m.emission(),
        };
    }
};
