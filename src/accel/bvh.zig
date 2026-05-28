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
        if (instances.len == 0) {
            return Bvh{
                .nodes = try alloc.alloc(Node, 0),
                .primitives = try alloc.alloc(InstanceRef, 0),
            };
        }

        // Make a mutable copy of the instances so we can reorder them.
        const primitives = try alloc.dupe(InstanceRef, instances);
        errdefer alloc.free(primitives);

        var nodes: std.ArrayList(Node) = .empty;
        errdefer nodes.deinit(alloc);

        _ = try buildRecursive(alloc, &nodes, primitives, 0, @intCast(primitives.len));

        return Bvh{
            .nodes = try nodes.toOwnedSlice(alloc),
            .primitives = primitives,
        };
    }

    // Recursively builds BVH nodes.  Returns the index of the node created for
    // the range [first, first+count).  Appends to `nodes` in a post-order
    // fashion so that each interior node's children are already in the list
    // when the interior node itself is appended.
    fn buildRecursive(
        alloc: std.mem.Allocator,
        nodes: *std.ArrayList(Node),
        primitives: []InstanceRef,
        first: u32,
        count: u32,
    ) !u32 {
        const NUM_BINS: usize = 16;

        // Compute the bounding AABB of all primitives in this range.
        var bounds = AABB.empty();
        for (primitives[first .. first + count]) |p| {
            bounds = bounds.expand(p.bbox);
        }

        // Leaf condition: too few primitives to bother splitting.
        if (count <= 4) {
            const idx: u32 = @intCast(nodes.items.len);
            try nodes.append(alloc, Node{
                .bounds = bounds,
                .left = first,
                .right = count,
                .is_leaf = true,
            });
            return idx;
        }

        // Centroid AABB for choosing the split axis and bin mapping.
        var centroid_bounds = AABB.empty();
        for (primitives[first .. first + count]) |p| {
            centroid_bounds = centroid_bounds.expandPoint(p.bbox.centroid());
        }

        const axis = centroid_bounds.longestAxis();

        // If the centroid AABB is degenerate on the longest axis, make a leaf.
        const axis_extent = switch (axis) {
            0 => centroid_bounds.max.x - centroid_bounds.min.x,
            1 => centroid_bounds.max.y - centroid_bounds.min.y,
            else => centroid_bounds.max.z - centroid_bounds.min.z,
        };

        if (axis_extent <= 0.0) {
            const idx: u32 = @intCast(nodes.items.len);
            try nodes.append(alloc, Node{
                .bounds = bounds,
                .left = first,
                .right = count,
                .is_leaf = true,
            });
            return idx;
        }

        // Binned SAH sweep.
        const BinData = struct {
            bounds: AABB,
            count: u32,
        };

        var bins: [NUM_BINS]BinData = undefined;
        for (&bins) |*b| {
            b.* = BinData{ .bounds = AABB.empty(), .count = 0 };
        }

        const inv_extent = 1.0 / axis_extent;
        for (primitives[first .. first + count]) |p| {
            const c = p.bbox.centroid();
            const c_axis = switch (axis) {
                0 => c.x,
                1 => c.y,
                else => c.z,
            };
            const c_min = switch (axis) {
                0 => centroid_bounds.min.x,
                1 => centroid_bounds.min.y,
                else => centroid_bounds.min.z,
            };
            const bin_f = (c_axis - c_min) * inv_extent * @as(f32, NUM_BINS);
            const bin_idx = @min(@as(usize, @intFromFloat(bin_f)), NUM_BINS - 1);
            bins[bin_idx].bounds = bins[bin_idx].bounds.expand(p.bbox);
            bins[bin_idx].count += 1;
        }

        // For each of the (NUM_BINS - 1) split planes, compute SAH cost.
        // left_sa[i]  = surface area of union of bins [0..i]
        // right_sa[i] = surface area of union of bins [i+1..NUM_BINS-1]
        var left_bounds: [NUM_BINS - 1]AABB = undefined;
        var left_count: [NUM_BINS - 1]u32 = undefined;
        {
            var acc_bounds = AABB.empty();
            var acc_count: u32 = 0;
            for (0..NUM_BINS - 1) |i| {
                acc_bounds = acc_bounds.expand(bins[i].bounds);
                acc_count += bins[i].count;
                left_bounds[i] = acc_bounds;
                left_count[i] = acc_count;
            }
        }

        var right_bounds: [NUM_BINS - 1]AABB = undefined;
        var right_count: [NUM_BINS - 1]u32 = undefined;
        {
            var acc_bounds = AABB.empty();
            var acc_count: u32 = 0;
            var i: usize = NUM_BINS - 1;
            while (i > 0) {
                i -= 1;
                acc_bounds = acc_bounds.expand(bins[i + 1].bounds);
                acc_count += bins[i + 1].count;
                right_bounds[i] = acc_bounds;
                right_count[i] = acc_count;
            }
        }

        // Find the cheapest split.
        var best_cost = std.math.floatMax(f32);
        var best_bin: usize = 0;
        for (0..NUM_BINS - 1) |i| {
            if (left_count[i] == 0 or right_count[i] == 0) continue;
            const cost = left_bounds[i].surfaceArea() * @as(f32, @floatFromInt(left_count[i])) +
                right_bounds[i].surfaceArea() * @as(f32, @floatFromInt(right_count[i]));
            if (cost < best_cost) {
                best_cost = cost;
                best_bin = i;
            }
        }

        // Compare against leaf cost (no traversal cost ratio needed for relative comparison).
        const leaf_cost = bounds.surfaceArea() * @as(f32, @floatFromInt(count));
        if (best_cost >= leaf_cost) {
            const idx: u32 = @intCast(nodes.items.len);
            try nodes.append(alloc, Node{
                .bounds = bounds,
                .left = first,
                .right = count,
                .is_leaf = true,
            });
            return idx;
        }

        // Partition primitives around the best split bin.
        // Primitives whose centroid bin index <= best_bin go left.
        var lo: usize = first;
        var hi: usize = first + count;
        while (lo < hi) {
            const p = primitives[lo];
            const c = p.bbox.centroid();
            const c_axis = switch (axis) {
                0 => c.x,
                1 => c.y,
                else => c.z,
            };
            const c_min = switch (axis) {
                0 => centroid_bounds.min.x,
                1 => centroid_bounds.min.y,
                else => centroid_bounds.min.z,
            };
            const bin_f = (c_axis - c_min) * inv_extent * @as(f32, NUM_BINS);
            const bin_idx = @min(@as(usize, @intFromFloat(bin_f)), NUM_BINS - 1);
            if (bin_idx <= best_bin) {
                lo += 1;
            } else {
                hi -= 1;
                primitives[lo] = primitives[hi];
                primitives[hi] = p;
            }
        }

        // lo is now the split point (first index of the right partition).
        // Guard against degenerate partitions (all on one side).
        const split = if (lo == first or lo == first + count)
            first + count / 2
        else
            lo;

        const left_count_split: u32 = @intCast(split - first);
        const right_count_split: u32 = count - left_count_split;

        // Recurse: children must be built before the parent node is appended.
        const left_idx = try buildRecursive(alloc, nodes, primitives, first, left_count_split);
        const right_idx = try buildRecursive(alloc, nodes, primitives, @intCast(split), right_count_split);

        const idx: u32 = @intCast(nodes.items.len);
        try nodes.append(alloc, Node{
            .bounds = bounds,
            .left = left_idx,
            .right = right_idx,
            .is_leaf = false,
        });
        return idx;
    }

    pub fn intersect(self: *const Bvh, ray: Ray) ?HitRecord {
        if (self.nodes.len == 0) return null;

        var stack: [32]u32 = undefined;
        var stack_top: usize = 0;

        // Root is the last node (post-order build).
        stack[stack_top] = @intCast(self.nodes.len - 1);
        stack_top += 1;

        var closest_t = ray.t_max;
        var best: HitRecord = undefined;
        var found = false;

        while (stack_top > 0) {
            stack_top -= 1;
            const node_idx = stack[stack_top];
            const node = self.nodes[node_idx];

            // Skip this node if its AABB is missed at [t_min, closest_t].
            if (!node.bounds.intersect(ray, ray.t_min, closest_t)) continue;

            if (node.is_leaf) {
                // Iterate leaf primitives.
                const first = node.left;
                const count = node.right;
                for (self.primitives[first .. first + count]) |prim| {
                    var hit: HitRecord = undefined;
                    if (prim.intersect(ray, ray.t_min, closest_t, &hit)) {
                        closest_t = hit.t;
                        best = hit;
                        found = true;
                    }
                }
            } else {
                // Interior node: test both children AABBs and push closer one last
                // so it is popped first (front-to-back ordering for early exit).
                const left_node = self.nodes[node.left];
                const right_node = self.nodes[node.right];

                const left_hit = left_node.bounds.intersect(ray, ray.t_min, closest_t);
                const right_hit = right_node.bounds.intersect(ray, ray.t_min, closest_t);

                if (left_hit and right_hit) {
                    // Determine which child is closer by comparing entry t values.
                    const left_t = aabbEntryT(left_node.bounds, ray);
                    const right_t = aabbEntryT(right_node.bounds, ray);

                    // Push farther child first so closer child is on top of stack.
                    if (left_t <= right_t) {
                        stack[stack_top] = node.right;
                        stack_top += 1;
                        stack[stack_top] = node.left;
                        stack_top += 1;
                    } else {
                        stack[stack_top] = node.left;
                        stack_top += 1;
                        stack[stack_top] = node.right;
                        stack_top += 1;
                    }
                } else if (left_hit) {
                    stack[stack_top] = node.left;
                    stack_top += 1;
                } else if (right_hit) {
                    stack[stack_top] = node.right;
                    stack_top += 1;
                }
            }
        }

        return if (found) best else null;
    }

    pub fn intersectAny(self: *const Bvh, ray: Ray, max_t: f32) bool {
        if (self.nodes.len == 0) return false;

        var stack: [32]u32 = undefined;
        var stack_top: usize = 0;

        // Root is the last node (post-order build).
        stack[stack_top] = @intCast(self.nodes.len - 1);
        stack_top += 1;

        while (stack_top > 0) {
            stack_top -= 1;
            const node_idx = stack[stack_top];
            const node = self.nodes[node_idx];

            // Skip this node if its AABB is missed.
            if (!node.bounds.intersect(ray, ray.t_min, max_t)) continue;

            if (node.is_leaf) {
                // Test each leaf primitive; return immediately on any hit.
                const first = node.left;
                const count = node.right;
                for (self.primitives[first .. first + count]) |prim| {
                    if (prim.intersectT(ray, ray.t_min, max_t)) |_| {
                        return true;
                    }
                }
            } else {
                // Push both children; order does not matter for correctness.
                stack[stack_top] = node.left;
                stack_top += 1;
                stack[stack_top] = node.right;
                stack_top += 1;
            }
        }

        return false;
    }

    // Returns the AABB entry t for front-to-back ordering.  Not clamped — used
    // only for child ordering comparisons, so the exact value doesn't matter as
    // long as it represents "how far along the ray the box starts".
    fn aabbEntryT(bounds: AABB, ray: Ray) f32 {
        const tx0 = (bounds.min.x - ray.origin.x) * ray.inv_dir.x;
        const tx1 = (bounds.max.x - ray.origin.x) * ray.inv_dir.x;
        const ty0 = (bounds.min.y - ray.origin.y) * ray.inv_dir.y;
        const ty1 = (bounds.max.y - ray.origin.y) * ray.inv_dir.y;
        const tz0 = (bounds.min.z - ray.origin.z) * ray.inv_dir.z;
        const tz1 = (bounds.max.z - ray.origin.z) * ray.inv_dir.z;
        return @max(@min(tx0, tx1), @max(@min(ty0, ty1), @min(tz0, tz1)));
    }

    pub fn deinit(self: *Bvh, alloc: std.mem.Allocator) void {
        alloc.free(self.nodes);
        alloc.free(self.primitives);
    }
};
