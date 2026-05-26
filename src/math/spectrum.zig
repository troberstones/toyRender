const std = @import("std");

pub const Spectrum = struct {
    r: f32,
    g: f32,
    b: f32,

    pub fn init(r: f32, g: f32, b: f32) Spectrum {
        return .{ .r = r, .g = g, .b = b };
    }

    pub fn splat(v: f32) Spectrum {
        return .{ .r = v, .g = v, .b = v };
    }

    pub fn zero() Spectrum {
        return splat(0.0);
    }

    pub fn one() Spectrum {
        return splat(1.0);
    }

    pub fn add(a: Spectrum, b: Spectrum) Spectrum {
        return .{ .r = a.r + b.r, .g = a.g + b.g, .b = a.b + b.b };
    }

    pub fn mul(a: Spectrum, b: Spectrum) Spectrum {
        return .{ .r = a.r * b.r, .g = a.g * b.g, .b = a.b * b.b };
    }

    pub fn scale(a: Spectrum, s: f32) Spectrum {
        return .{ .r = a.r * s, .g = a.g * s, .b = a.b * s };
    }

    pub fn isBlack(a: Spectrum) bool {
        return a.r == 0.0 and a.g == 0.0 and a.b == 0.0;
    }

    pub fn luminance(a: Spectrum) f32 {
        return 0.2126 * a.r + 0.7152 * a.g + 0.0722 * a.b;
    }

    pub fn lerp(a: Spectrum, b: Spectrum, t: f32) Spectrum {
        return add(scale(a, 1.0 - t), scale(b, t));
    }

    // Clamp each channel to [0, inf).
    pub fn clampNeg(a: Spectrum) Spectrum {
        return .{
            .r = @max(a.r, 0.0),
            .g = @max(a.g, 0.0),
            .b = @max(a.b, 0.0),
        };
    }
};
