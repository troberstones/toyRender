// Performance counters — a lightweight way to measure rays/sec, sample throughput, etc.
const std = @import("std");

pub const Counters = struct {
    rays_cast: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    shadow_rays: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    bvh_traversals: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    samples_completed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    start_ns: i128 = 0,

    pub fn start(self: *Counters) void {
        self.start_ns = std.time.nanoTimestamp();
    }

    pub fn addRay(self: *Counters) void {
        _ = self.rays_cast.fetchAdd(1, .monotonic);
    }

    pub fn addShadowRay(self: *Counters) void {
        _ = self.shadow_rays.fetchAdd(1, .monotonic);
    }

    pub fn addBvhTraversal(self: *Counters) void {
        _ = self.bvh_traversals.fetchAdd(1, .monotonic);
    }

    pub fn addSamples(self: *Counters, n: u64) void {
        _ = self.samples_completed.fetchAdd(n, .monotonic);
    }

    pub fn report(self: *const Counters, writer: anytype) !void {
        const elapsed_ns = std.time.nanoTimestamp() - self.start_ns;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) * 1e-9;
        const rays = self.rays_cast.load(.monotonic);
        const samples = self.samples_completed.load(.monotonic);

        try writer.print(
            \\--- Performance ---
            \\  Elapsed:       {d:.3}s
            \\  Rays cast:     {}  ({d:.1} Mrays/s)
            \\  Shadow rays:   {}
            \\  BVH queries:   {}
            \\  Samples:       {}  ({d:.1}k spp/s)
            \\
        , .{
            elapsed_s,
            rays,
            @as(f64, @floatFromInt(rays)) / elapsed_s * 1e-6,
            self.shadow_rays.load(.monotonic),
            self.bvh_traversals.load(.monotonic),
            samples,
            @as(f64, @floatFromInt(samples)) / elapsed_s * 1e-3,
        });
    }
};

pub var global = Counters{};

test "counters compile" {
    var c = Counters{};
    c.start();
    c.addRay();
    c.addSamples(1);
    // Just confirm it compiles and doesn't panic.
}
