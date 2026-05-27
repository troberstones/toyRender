// Performance counters — lightweight measurement of rays/sec, sample throughput, etc.
const std = @import("std");

pub const Counters = struct {
    rays_cast: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    shadow_rays: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    bvh_traversals: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    samples_completed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    start_ns: i128 = 0,

    pub fn start(self: *Counters) void {
        self.start_ns = monoNs();
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

    pub fn elapsedNs(self: *const Counters) i128 {
        return monoNs() - self.start_ns;
    }

    /// One-line progress update for in-loop printing (writes to stderr via std.debug.print).
    /// Call this roughly once per second; uses \r to overwrite the same terminal line.
    pub fn printProgress(self: *const Counters, spp_done: u32, spp_total: u32) void {
        const elapsed_ns = self.elapsedNs();
        if (elapsed_ns <= 0) return;
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) * 1e-9;
        const path  = self.rays_cast.load(.monotonic);
        const shad  = self.shadow_rays.load(.monotonic);
        const total = path + shad;
        const mrays = @as(f64, @floatFromInt(total)) / elapsed_s * 1e-6;
        std.debug.print(
            "\r[{d:>3}/{d} spp | {d:>5.1}s]  {d:.2} Mrays/s   ",
            .{ spp_done, spp_total, elapsed_s, mrays },
        );
    }

    /// Final summary printed after rendering completes.
    pub fn report(self: *const Counters, writer: anytype) !void {
        const elapsed_ns = self.elapsedNs();
        const elapsed_s  = @as(f64, @floatFromInt(@max(elapsed_ns, 1))) * 1e-9;
        const path       = self.rays_cast.load(.monotonic);
        const shad       = self.shadow_rays.load(.monotonic);
        const total      = path + shad;
        const samples    = self.samples_completed.load(.monotonic);

        try writer.print(
            \\
            \\--- Performance ---
            \\  Elapsed:       {d:.3}s
            \\  Path rays:     {d}
            \\  Shadow rays:   {d}
            \\  Total Mrays/s: {d:.2}
            \\  Samples:       {d}  ({d:.1}k spp/s)
            \\
        , .{
            elapsed_s,
            path,
            shad,
            @as(f64, @floatFromInt(total)) / elapsed_s * 1e-6,
            samples,
            @as(f64, @floatFromInt(samples)) / elapsed_s * 1e-3,
        });
    }
};

pub var global = Counters{};

fn monoNs() i128 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

test "counters compile" {
    var c = Counters{};
    c.start();
    c.addRay();
    c.addShadowRay();
    c.addSamples(1);
    // Just confirm it compiles and doesn't panic.
}
