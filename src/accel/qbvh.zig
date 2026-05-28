const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Ray = math.Ray;
const AABB = math.AABB;
const AabbPack = math.AabbPack;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;
const InstanceRef = @import("instance_ref.zig").InstanceRef;
const Bvh = @import("bvh.zig").Bvh;

/// A 4-wide BVH interior node.
/// Each node stores 4 children's bounds in SoA AabbPack format.
/// Child encoding:
///   - Leaf child:     child_prim_count[i] > 0, child_idx[i] = first prim index
///   - Interior child: child_prim_count[i] = 0, child_idx[i] = qnode index
///   - Unused slot:    child_prim_count[i] = 0, child_idx[i] = std.math.maxInt(u32)
const QNode = struct {
    children_bounds: AabbPack,
    child_idx: [4]u32,
    child_prim_count: [4]u32,
};

pub const Qbvh = struct {
    qnodes: []QNode,
    primitives: []InstanceRef,
    root: u32,

    /// Build a QBVH by collapsing an existing binary BVH.
    /// `fromBvh` duplicates the primitives slice so that both the Bvh and Qbvh
    /// can be deinitialized independently (caller frees bvh normally).
    pub fn fromBvh(alloc: std.mem.Allocator, bvh: Bvh) !Qbvh {
        if (bvh.nodes.len == 0) {
            return Qbvh{
                .qnodes = try alloc.alloc(QNode, 0),
                .primitives = try alloc.alloc(InstanceRef, 0),
                .root = 0,
            };
        }

        // Duplicate primitives so qbvh owns its own copy.
        const primitives = try alloc.dupe(InstanceRef, bvh.primitives);
        errdefer alloc.free(primitives);

        var qnodes: std.ArrayList(QNode) = .empty;
        errdefer qnodes.deinit(alloc);

        const binary_root: u32 = @intCast(bvh.nodes.len - 1);
        const qroot = try buildNodeRecursive(alloc, &qnodes, bvh, binary_root);

        return Qbvh{
            .qnodes = try qnodes.toOwnedSlice(alloc),
            .primitives = primitives,
            .root = qroot,
        };
    }

    /// Describes one slot in the 4-child QBVH node being built.
    const Slot = struct {
        bounds: AABB,
        /// true  → leaf: first = prim offset, count = prim count
        /// false → interior: first = binary node index to recurse into, count unused
        /// unused slot: first = maxInt(u32)
        is_leaf: bool,
        first: u32,
        count: u32,
    };

    /// Push one binary node's contribution into the slot array.
    /// If the binary node is a leaf it occupies one slot.
    /// If it is interior its two children each occupy one slot (grandchild expansion).
    fn expandBinaryNode(
        slots: *[4]Slot,
        slot_count: *usize,
        child_bin_idx: u32,
        bvh: Bvh,
    ) void {
        const child = bvh.nodes[child_bin_idx];
        if (child.is_leaf) {
            slots[slot_count.*] = .{
                .bounds = child.bounds,
                .is_leaf = true,
                .first = child.left,
                .count = child.right,
            };
            slot_count.* += 1;
        } else {
            // Expand into this node's two children (grandchildren of the root node).
            const lc = bvh.nodes[child.left];
            slots[slot_count.*] = .{
                .bounds = lc.bounds,
                .is_leaf = lc.is_leaf,
                .first = if (lc.is_leaf) lc.left else child.left,
                .count = if (lc.is_leaf) lc.right else 0,
            };
            slot_count.* += 1;

            if (slot_count.* < 4) {
                const rc = bvh.nodes[child.right];
                slots[slot_count.*] = .{
                    .bounds = rc.bounds,
                    .is_leaf = rc.is_leaf,
                    .first = if (rc.is_leaf) rc.left else child.right,
                    .count = if (rc.is_leaf) rc.right else 0,
                };
                slot_count.* += 1;
            }
        }
    }

    /// Recursively collapse a binary BVH node (and its grandchildren) into a
    /// single QNode with up to 4 children.
    fn buildNodeRecursive(
        alloc: std.mem.Allocator,
        qnodes: *std.ArrayList(QNode),
        bvh: Bvh,
        bin_idx: u32,
    ) !u32 {
        const node = bvh.nodes[bin_idx];

        if (node.is_leaf) {
            // Binary leaf becomes a QBVH node with one leaf child and 3 unused slots.
            const q_idx: u32 = @intCast(qnodes.items.len);
            try qnodes.append(alloc, QNode{
                .children_bounds = AabbPack.init(.{
                    node.bounds,
                    AABB.empty(),
                    AABB.empty(),
                    AABB.empty(),
                }),
                .child_idx = .{ node.left, std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32) },
                .child_prim_count = .{ node.right, 0, 0, 0 },
            });
            return q_idx;
        }

        // Interior node: gather up to 4 grandchildren by expanding left and right.
        var slots: [4]Slot = undefined;
        var slot_count: usize = 0;

        expandBinaryNode(&slots, &slot_count, node.left, bvh);
        expandBinaryNode(&slots, &slot_count, node.right, bvh);

        // Pad unused slots.
        while (slot_count < 4) : (slot_count += 1) {
            slots[slot_count] = .{
                .bounds = AABB.empty(),
                .is_leaf = false,
                .first = std.math.maxInt(u32),
                .count = 0,
            };
        }

        // Allocate a placeholder node; patch it after children are built
        // (children's recursion may realloc the ArrayList, so we keep the index
        //  and re-index after).
        const q_idx: u32 = @intCast(qnodes.items.len);
        try qnodes.append(alloc, QNode{
            .children_bounds = AabbPack.init(.{
                slots[0].bounds,
                slots[1].bounds,
                slots[2].bounds,
                slots[3].bounds,
            }),
            .child_idx = .{ 0, 0, 0, 0 },
            .child_prim_count = .{ 0, 0, 0, 0 },
        });

        var child_idx_arr: [4]u32 = .{ std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32), std.math.maxInt(u32) };
        var child_prim_count_arr: [4]u32 = .{ 0, 0, 0, 0 };

        for (0..4) |i| {
            const s = slots[i];
            if (s.first == std.math.maxInt(u32)) {
                // Unused slot — leave maxInt sentinel.
            } else if (s.is_leaf) {
                child_idx_arr[i] = s.first;
                child_prim_count_arr[i] = s.count;
            } else {
                // Interior grandchild: recurse and store the resulting qnode index.
                const child_qidx = try buildNodeRecursive(alloc, qnodes, bvh, s.first);
                child_idx_arr[i] = child_qidx;
            }
        }

        // Patch the placeholder now that all children are resolved.
        qnodes.items[q_idx].child_idx = child_idx_arr;
        qnodes.items[q_idx].child_prim_count = child_prim_count_arr;

        return q_idx;
    }

    /// Nearest-hit traversal.
    pub fn intersect(self: *const Qbvh, ray: Ray) ?HitRecord {
        if (self.qnodes.len == 0) return null;

        var stack: [64]u32 = undefined;
        var stack_top: usize = 0;

        stack[stack_top] = self.root;
        stack_top += 1;

        var closest_t = ray.t_max;
        var best: HitRecord = undefined;
        var found = false;

        while (stack_top > 0) {
            stack_top -= 1;
            const qnode_idx = stack[stack_top];
            const qnode = &self.qnodes[qnode_idx];

            // Test all 4 child AABBs simultaneously.
            const entry_t_vec = qnode.children_bounds.intersect4(ray, ray.t_min, closest_t);
            const entry_t: [4]f32 = entry_t_vec;
            const inf = std.math.floatMax(f32);

            // Collect hit children with their entry t values.
            const Hit = struct { t: f32, idx: u32 };
            var hits: [4]Hit = undefined;
            var hit_count: usize = 0;

            for (0..4) |i| {
                if (entry_t[i] < inf) {
                    hits[hit_count] = .{ .t = entry_t[i], .idx = @intCast(i) };
                    hit_count += 1;
                }
            }

            // Sort hit children by t (insertion sort — at most 4 elements).
            for (1..hit_count) |j| {
                const key = hits[j];
                var k: usize = j;
                while (k > 0 and hits[k - 1].t > key.t) : (k -= 1) {
                    hits[k] = hits[k - 1];
                }
                hits[k] = key;
            }

            // Push children onto the stack in reverse order (farthest first so
            // the closest child is popped first).
            var h: usize = hit_count;
            while (h > 0) {
                h -= 1;
                const ci = hits[h].idx;
                const prim_count = qnode.child_prim_count[ci];
                const child_i = qnode.child_idx[ci];

                if (prim_count > 0) {
                    // Leaf: test primitives directly.
                    for (self.primitives[child_i .. child_i + prim_count]) |prim| {
                        var hit: HitRecord = undefined;
                        if (prim.intersect(ray, ray.t_min, closest_t, &hit)) {
                            closest_t = hit.t;
                            best = hit;
                            found = true;
                        }
                    }
                } else if (child_i != std.math.maxInt(u32)) {
                    // Interior: push qnode index.
                    stack[stack_top] = child_i;
                    stack_top += 1;
                }
            }
        }

        return if (found) best else null;
    }

    /// Any-hit traversal (early exit for shadow rays).
    pub fn intersectAny(self: *const Qbvh, ray: Ray, max_t: f32) bool {
        if (self.qnodes.len == 0) return false;

        var stack: [64]u32 = undefined;
        var stack_top: usize = 0;

        stack[stack_top] = self.root;
        stack_top += 1;

        while (stack_top > 0) {
            stack_top -= 1;
            const qnode_idx = stack[stack_top];
            const qnode = &self.qnodes[qnode_idx];

            const entry_t_vec = qnode.children_bounds.intersect4(ray, ray.t_min, max_t);
            const entry_t: [4]f32 = entry_t_vec;
            const inf = std.math.floatMax(f32);

            for (0..4) |i| {
                if (entry_t[i] >= inf) continue;

                const prim_count = qnode.child_prim_count[i];
                const child_i = qnode.child_idx[i];

                if (prim_count > 0) {
                    for (self.primitives[child_i .. child_i + prim_count]) |prim| {
                        if (prim.intersectT(ray, ray.t_min, max_t)) |_| {
                            return true;
                        }
                    }
                } else if (child_i != std.math.maxInt(u32)) {
                    stack[stack_top] = child_i;
                    stack_top += 1;
                }
            }
        }

        return false;
    }

    pub fn deinit(self: *Qbvh, alloc: std.mem.Allocator) void {
        alloc.free(self.qnodes);
        alloc.free(self.primitives);
    }
};
