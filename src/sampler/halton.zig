// Halton sequence in base-2 and base-3 (first two dimensions).
// For higher dimensions, extend with primes 5, 7, 11, ...
pub const Halton = struct {
    index: u32, // global sample index
    pixel_offset: u32,

    pub fn init() Halton {
        return .{ .index = 0, .pixel_offset = 0 };
    }

    pub fn startPixel(self: *Halton, px: u32, py: u32, sample_idx: u32) void {
        // Scramble per-pixel to decorrelate neighboring pixels.
        self.pixel_offset = px * 1234567 +% py * 7654321;
        self.index = sample_idx;
    }

    pub fn next1d(self: *Halton) f32 {
        const v = radical_inverse(self.index +% self.pixel_offset, 2);
        self.index +%= 1;
        return v;
    }

    pub fn next2d(self: *Halton) [2]f32 {
        const idx = self.index +% self.pixel_offset;
        const v = [2]f32{
            radical_inverse(idx, 2),
            radical_inverse(idx, 3),
        };
        self.index +%= 1;
        return v;
    }

    fn radical_inverse(n_in: u32, base: u32) f32 {
        var n = n_in;
        var f: f32 = 1.0;
        var r: f32 = 0.0;
        const fb = @as(f32, @floatFromInt(base));
        while (n > 0) {
            f /= fb;
            r += f * @as(f32, @floatFromInt(n % base));
            n /= base;
        }
        return r;
    }
};
