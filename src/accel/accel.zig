const std = @import("std");
const math = @import("math");
const Ray = math.Ray;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const Instance = @import("instance_ref.zig").InstanceRef;

const BruteForce = @import("brute_force.zig").BruteForce;
const Bvh = @import("bvh.zig").Bvh;
const Qbvh = @import("qbvh.zig").Qbvh;

// Each variant must implement:
//   fn intersect(self: *T, ray: Ray) ?HitRecord
//   fn intersectAny(self: *T, ray: Ray, max_t: f32) bool
pub const AccelStructure = union(enum) {
    brute_force: BruteForce,
    bvh: Bvh,
    qbvh: Qbvh,

    pub fn intersect(self: *const AccelStructure, ray: Ray) ?HitRecord {
        return switch (self.*) {
            inline else => |*a| a.intersect(ray),
        };
    }

    pub fn intersectAny(self: *const AccelStructure, ray: Ray, max_t: f32) bool {
        return switch (self.*) {
            inline else => |*a| a.intersectAny(ray, max_t),
        };
    }

    pub fn deinit(self: *AccelStructure, alloc: std.mem.Allocator) void {
        switch (self.*) {
            .bvh => |*b| b.deinit(alloc),
            .qbvh => |*q| q.deinit(alloc),
            .brute_force => {}, // no heap allocations
        }
    }
};
