const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const Ray = math.Ray;

const PointLight = @import("point_light.zig").PointLight;
const AreaLight = @import("area_light.zig").AreaLight;
const EnvLight = @import("env_light.zig").EnvLight;

pub const LightSample = struct {
    li: Spectrum,   // incident radiance
    wi: Vec3,       // direction *toward* the light
    pdf: f32,       // w.r.t. solid angle at the hit point
    dist: f32,      // distance to the light (inf for env)
};

// Each variant must implement:
//   fn sampleLi(self, hit_point: Vec3, rng: [2]f32) ?LightSample
//   fn pdfLi(self, hit_point: Vec3, wi: Vec3) f32
//   fn le(self, ray: Ray) Spectrum   (emitted radiance for area/env lights)
//   fn isDelta(self) bool            (point lights have delta distributions)
pub const Light = union(enum) {
    point: PointLight,
    area: AreaLight,
    env: EnvLight,

    pub fn sampleLi(self: Light, hit_point: Vec3, rng: [2]f32) ?LightSample {
        return switch (self) {
            inline else => |l| l.sampleLi(hit_point, rng),
        };
    }

    pub fn pdfLi(self: Light, hit_point: Vec3, wi: Vec3) f32 {
        return switch (self) {
            inline else => |l| l.pdfLi(hit_point, wi),
        };
    }

    pub fn le(self: Light, ray: Ray) Spectrum {
        return switch (self) {
            inline else => |l| l.le(ray),
        };
    }

    pub fn isDelta(self: Light) bool {
        return switch (self) {
            inline else => |l| l.isDelta(),
        };
    }
};
