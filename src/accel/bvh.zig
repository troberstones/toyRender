const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Ray = math.Ray;
const AABB = math.AABB;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const InstanceRef = @import("instance_ref.zig").InstanceRef;

const Node = struct {
    bounds: AABB,
    // Leaf: left = first_prim index, right = prim_count (packed).
    // Interior: left/right are child node indices.
    left: u32,
    right: u32,
    is_leaf: bool,
};

pub const Bvh = struct {
    nodes: []Node,
    primitives: []InstanceRef, // reordered during build

    // Build a SAH BVH over the given instances.
    pub fn build(alloc: std.mem.Allocator, instances: []InstanceRef) !Bvh {
        _ = alloc;
        _ = instances;
        // TODO: implement recursive SAH BVH build
        //   1. Compute centroid AABB
        //   2. For each axis, sweep N bins and find minimum SAH cost split
        //   3. Partition primitives, recurse
        @panic("Bvh.build not yet implemented");
    }

    pub fn intersect(self: *Bvh, ray: Ray) ?HitRecord {
        _ = self;
        _ = ray;
        // TODO: iterative traversal with a small stack
        @panic("Bvh.intersect not yet implemented");
    }

    pub fn intersectAny(self: *Bvh, ray: Ray, max_t: f32) bool {
        _ = self;
        _ = ray;
        _ = max_t;
        // TODO: early-exit traversal
        @panic("Bvh.intersectAny not yet implemented");
    }

    pub fn deinit(self: *Bvh, alloc: std.mem.Allocator) void {
        alloc.free(self.nodes);
        alloc.free(self.primitives);
    }
};
