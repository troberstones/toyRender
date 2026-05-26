// PCG32 random number generator — period 2^64, excellent statistical quality.
pub const Independent = struct {
    state: u64,
    inc: u64,

    pub fn init(seed: u64) Independent {
        var s = Independent{ .state = 0, .inc = (seed << 1) | 1 };
        _ = s.nextU32();
        s.state +%= seed;
        _ = s.nextU32();
        return s;
    }

    pub fn startPixel(self: *Independent, px: u32, py: u32, sample_idx: u32) void {
        const seed = @as(u64, px) * 1000003 + @as(u64, py) * 1000033 + @as(u64, sample_idx);
        self.* = init(seed);
    }

    pub fn next1d(self: *Independent) f32 {
        return @as(f32, @floatFromInt(self.nextU32())) * 2.3283064365386963e-10; // 1/2^32
    }

    pub fn next2d(self: *Independent) [2]f32 {
        return .{ self.next1d(), self.next1d() };
    }

    fn nextU32(self: *Independent) u32 {
        const old = self.state;
        self.state = old *% 6364136223846793005 +% self.inc;
        const xorshifted: u32 = @truncate(((old >> 18) ^ old) >> 27);
        const rot: u32 = @truncate(old >> 59);
        return (xorshifted >> @truncate(rot)) | (xorshifted << @truncate((-%rot) & 31));
    }
};
