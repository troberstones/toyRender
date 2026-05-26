const Independent = @import("independent.zig").Independent;
const Halton = @import("halton.zig").Halton;

// Each variant must implement:
//   fn startPixel(self: *T, px: u32, py: u32, sample_idx: u32) void
//   fn next1d(self: *T) f32       -- returns value in [0, 1)
//   fn next2d(self: *T) [2]f32    -- returns pair in [0,1)^2
pub const Sampler = union(enum) {
    independent: Independent,
    halton: Halton,

    pub fn startPixel(self: *Sampler, px: u32, py: u32, sample_idx: u32) void {
        switch (self.*) {
            inline else => |*s| s.startPixel(px, py, sample_idx),
        }
    }

    pub fn next1d(self: *Sampler) f32 {
        return switch (self.*) {
            inline else => |*s| s.next1d(),
        };
    }

    pub fn next2d(self: *Sampler) [2]f32 {
        return switch (self.*) {
            inline else => |*s| s.next2d(),
        };
    }
};
