const math = @import("math");
const Spectrum = math.Spectrum;

pub const Tonemap = union(enum) {
    linear,
    reinhard,
    aces,

    pub fn apply(self: Tonemap, s: Spectrum) Spectrum {
        return switch (self) {
            .linear => s,
            .reinhard => reinhardTonemap(s),
            .aces => acesTonemap(s),
        };
    }

    fn reinhardTonemap(s: Spectrum) Spectrum {
        return .{
            .r = s.r / (1.0 + s.r),
            .g = s.g / (1.0 + s.g),
            .b = s.b / (1.0 + s.b),
        };
    }

    fn acesTonemap(s: Spectrum) Spectrum {
        // ACES filmic approximation (Narkowicz 2015)
        const a = 2.51;
        const b = 0.03;
        const c = 2.43;
        const d = 0.59;
        const e = 0.14;
        return .{
            .r = acesChannel(s.r, a, b, c, d, e),
            .g = acesChannel(s.g, a, b, c, d, e),
            .b = acesChannel(s.b, a, b, c, d, e),
        };
    }

    fn acesChannel(x: f32, a: f32, b: f32, c: f32, d: f32, e: f32) f32 {
        const num = x * (a * x + b);
        const den = x * (c * x + d) + e;
        return @max(0.0, @min(1.0, num / den));
    }
};
