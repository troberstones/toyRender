const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const Ray = math.Ray;
const LightSample = @import("light.zig").LightSample;

pub const EnvLight = struct {
    // HDRI map: width x height texels in lat-long format.
    texels: ?[]const Spectrum,
    width: u32,
    height: u32,
    // Uniform tint used when texels == null.
    tint: Spectrum,

    pub fn sampleLi(self: EnvLight, hit_point: Vec3, rng: [2]f32) ?LightSample {
        _ = hit_point;
        // TODO: importance-sample the environment map
        // Uniform sphere sampling as placeholder
        const z = 1.0 - 2.0 * rng[0];
        const r = @sqrt(@max(0.0, 1.0 - z * z));
        const phi = 2.0 * std.math.pi * rng[1];
        const wi = Vec3.init(r * @cos(phi), r * @sin(phi), z);
        return LightSample{
            .li = self.tint,
            .wi = wi,
            .pdf = 1.0 / (4.0 * std.math.pi),
            .dist = std.math.floatMax(f32),
        };
    }

    pub fn pdfLi(self: EnvLight, hit_point: Vec3, wi: Vec3) f32 {
        _ = self;
        _ = hit_point;
        _ = wi;
        // TODO: return pdf from importance-sampling distribution
        return 1.0 / (4.0 * std.math.pi);
    }

    pub fn le(self: EnvLight, ray: Ray) Spectrum {
        if (self.texels) |tex| {
            return sampleLatLong(tex, self.width, self.height, ray.direction);
        }
        return self.tint;
    }

    pub fn isDelta(self: EnvLight) bool {
        _ = self;
        return false;
    }

    fn sampleLatLong(
        tex: []const Spectrum,
        w: u32,
        h: u32,
        dir: Vec3,
    ) Spectrum {
        const phi = std.math.atan2(dir.z, dir.x) + std.math.pi;
        const theta = std.math.acos(std.math.clamp(dir.y, -1.0, 1.0));
        const u = phi / (2.0 * std.math.pi);
        const v = theta / std.math.pi;
        const px = @min(@as(u32, @intFromFloat(u * @as(f32, @floatFromInt(w)))), w - 1);
        const py = @min(@as(u32, @intFromFloat(v * @as(f32, @floatFromInt(h)))), h - 1);
        return tex[py * w + px];
    }
};
