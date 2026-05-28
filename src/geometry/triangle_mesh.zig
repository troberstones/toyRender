const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Ray = math.Ray;
const AABB = math.AABB;
const HitRecord = @import("geometry.zig").HitRecord;
const SurfaceSample = @import("geometry.zig").SurfaceSample;

pub const Vertex = struct {
    position: Vec3,
    normal: Vec3,
    uv: [2]f32,
};

pub const Triangle = struct {
    indices: [3]u32,
};

/// SoA layout holding 4 triangles for 4-wide SIMD Möller–Trumbore intersection.
/// Stores v0 position and the two edge vectors (e1 = v1-v0, e2 = v2-v0) per lane.
pub const TrianglePack = struct {
    // Vertex 0 positions
    v0x: @Vector(4, f32),
    v0y: @Vector(4, f32),
    v0z: @Vector(4, f32),
    // Edge 1 = v1 - v0
    e1x: @Vector(4, f32),
    e1y: @Vector(4, f32),
    e1z: @Vector(4, f32),
    // Edge 2 = v2 - v0
    e2x: @Vector(4, f32),
    e2y: @Vector(4, f32),
    e2z: @Vector(4, f32),

    /// Fill lanes 0..count-1 from mesh triangles starting at `first`.
    /// Remaining lanes are padded with a degenerate triangle (det=0 → always miss).
    /// `count` must be 1–4.
    pub fn init(mesh: *const TriangleMesh, first: u32, count: u32) TrianglePack {
        std.debug.assert(count >= 1 and count <= 4);

        var v0x: [4]f32 = .{ 0, 0, 0, 0 };
        var v0y: [4]f32 = .{ 0, 0, 0, 0 };
        var v0z: [4]f32 = .{ 0, 0, 0, 0 };
        var e1x: [4]f32 = .{ 0, 0, 0, 0 };
        var e1y: [4]f32 = .{ 0, 0, 0, 0 };
        var e1z: [4]f32 = .{ 0, 0, 0, 0 };
        var e2x: [4]f32 = .{ 0, 0, 0, 0 };
        var e2y: [4]f32 = .{ 0, 0, 0, 0 };
        var e2z: [4]f32 = .{ 0, 0, 0, 0 };

        var lane: u32 = 0;
        while (lane < count) : (lane += 1) {
            const tri = mesh.triangles[first + lane];
            const p0 = mesh.vertices[tri.indices[0]].position;
            const p1 = mesh.vertices[tri.indices[1]].position;
            const p2 = mesh.vertices[tri.indices[2]].position;
            v0x[lane] = p0.x;
            v0y[lane] = p0.y;
            v0z[lane] = p0.z;
            e1x[lane] = p1.x - p0.x;
            e1y[lane] = p1.y - p0.y;
            e1z[lane] = p1.z - p0.z;
            e2x[lane] = p2.x - p0.x;
            e2y[lane] = p2.y - p0.y;
            e2z[lane] = p2.z - p0.z;
            // Degenerate padding lanes (lane >= count) keep e1=e2=0 which gives det=0 → miss.
        }

        return .{
            .v0x = v0x,
            .v0y = v0y,
            .v0z = v0z,
            .e1x = e1x,
            .e1y = e1y,
            .e1z = e1z,
            .e2x = e2x,
            .e2y = e2y,
            .e2z = e2z,
        };
    }
};

/// 4-wide Möller–Trumbore t-only test.
/// Returns the hit t for each lane; miss lanes return std.math.floatMax(f32).
pub fn intersectT4(pack: TrianglePack, ray: Ray, t_min: f32, t_max: f32) @Vector(4, f32) {
    const inf4: @Vector(4, f32) = @splat(std.math.floatMax(f32));
    const eps: @Vector(4, f32) = @splat(1e-8);
    const zero4: @Vector(4, f32) = @splat(0.0);
    const one4: @Vector(4, f32) = @splat(1.0);
    const tmin4: @Vector(4, f32) = @splat(t_min);
    const tmax4: @Vector(4, f32) = @splat(t_max);

    // Broadcast ray fields.
    const rdx: @Vector(4, f32) = @splat(ray.direction.x);
    const rdy: @Vector(4, f32) = @splat(ray.direction.y);
    const rdz: @Vector(4, f32) = @splat(ray.direction.z);
    const rox: @Vector(4, f32) = @splat(ray.origin.x);
    const roy: @Vector(4, f32) = @splat(ray.origin.y);
    const roz: @Vector(4, f32) = @splat(ray.origin.z);

    // h = cross(ray.direction, e2)
    const hx = rdy * pack.e2z - rdz * pack.e2y;
    const hy = rdz * pack.e2x - rdx * pack.e2z;
    const hz = rdx * pack.e2y - rdy * pack.e2x;

    // det = dot(e1, h)
    const det = pack.e1x * hx + pack.e1y * hy + pack.e1z * hz;

    // Parallel test: |det| < eps → miss
    const abs_det = @abs(det);
    const not_parallel = abs_det >= eps;

    // inv_det = 1 / det (safe: parallel lanes will be masked out by @select)
    // Use a safe divisor to avoid division by zero in degenerate lanes.
    const safe_det = @select(f32, not_parallel, det, one4);
    const inv_det = one4 / safe_det;

    // s = ray.origin - v0
    const sx = rox - pack.v0x;
    const sy = roy - pack.v0y;
    const sz = roz - pack.v0z;

    // u = dot(s, h) * inv_det
    const u = (sx * hx + sy * hy + sz * hz) * inv_det;
    const u_ok = (u >= zero4) & (u <= one4);

    // q = cross(s, e1)
    const qx = sy * pack.e1z - sz * pack.e1y;
    const qy = sz * pack.e1x - sx * pack.e1z;
    const qz = sx * pack.e1y - sy * pack.e1x;

    // v = dot(ray.direction, q) * inv_det
    const v = (rdx * qx + rdy * qy + rdz * qz) * inv_det;
    const v_ok = (v >= zero4) & (u + v <= one4);

    // t = dot(e2, q) * inv_det
    const t = (pack.e2x * qx + pack.e2y * qy + pack.e2z * qz) * inv_det;
    const t_ok = (t >= tmin4) & (t <= tmax4);

    // All conditions must hold.
    const hit = not_parallel & u_ok & v_ok & t_ok;
    return @select(f32, hit, t, inf4);
}

/// Full hit test for 4 triangles: finds the closest hit and fills `out` via the scalar path.
/// Returns true if any lane hit.
pub fn intersect4(
    pack: TrianglePack,
    mesh: *const TriangleMesh,
    first: u32,
    count: u32,
    ray: Ray,
    t_min: f32,
    t_max: f32,
    out: *HitRecord,
) bool {
    const ts = intersectT4(pack, ray, t_min, t_max);
    const inf = std.math.floatMax(f32);

    // Find lane with minimum finite t ≤ t_max.
    // Use inline for so lane indices are comptime known.
    var best_t: f32 = t_max;
    var best_lane: i32 = -1;
    inline for (0..4) |lane| {
        if (lane < count) {
            const ti = ts[lane];
            if (ti < inf and ti <= best_t) {
                best_t = ti;
                best_lane = @intCast(lane);
            }
        }
    }

    if (best_lane < 0) return false;

    // Use scalar path to fill out the full HitRecord for the winning triangle.
    const tri = mesh.triangles[first + @as(u32, @intCast(best_lane))];
    // Re-call scalar with the tight t_max=best_t to guarantee the same result.
    return mesh.intersectTriangle(tri, ray, t_min, best_t, out);
}

pub const TriangleMesh = struct {
    vertices: []const Vertex,
    triangles: []const Triangle,
    material_index: u32,
    // Precomputed bounding box over all vertices.
    bounds: AABB,

    pub fn intersect(self: TriangleMesh, ray: Ray, t_min: f32, t_max: f32, out: *HitRecord) bool {
        var closest = t_max;
        var found = false;

        var i: u32 = 0;
        while (i < self.triangles.len) : (i += 4) {
            const count: u32 = @intCast(@min(4, self.triangles.len - i));
            const pack = TrianglePack.init(&self, i, count);
            if (intersect4(pack, &self, i, count, ray, t_min, closest, out)) {
                closest = out.t;
                found = true;
            }
        }
        return found;
    }

    fn intersectTriangle(
        self: TriangleMesh,
        tri: Triangle,
        ray: Ray,
        t_min: f32,
        t_max: f32,
        out: *HitRecord,
    ) bool {
        const v0 = self.vertices[tri.indices[0]].position;
        const v1 = self.vertices[tri.indices[1]].position;
        const v2 = self.vertices[tri.indices[2]].position;

        // Möller–Trumbore intersection
        const e1 = Vec3.sub(v1, v0);
        const e2 = Vec3.sub(v2, v0);
        const h = Vec3.cross(ray.direction, e2);
        const det = Vec3.dot(e1, h);

        if (@abs(det) < 1e-8) return false; // parallel

        const inv_det = 1.0 / det;
        const s = Vec3.sub(ray.origin, v0);
        const u = Vec3.dot(s, h) * inv_det;
        if (u < 0.0 or u > 1.0) return false;

        const q = Vec3.cross(s, e1);
        const v = Vec3.dot(ray.direction, q) * inv_det;
        if (v < 0.0 or u + v > 1.0) return false;

        const t = Vec3.dot(e2, q) * inv_det;
        if (t < t_min or t > t_max) return false;

        const w = 1.0 - u - v;
        const n0 = self.vertices[tri.indices[0]].normal;
        const n1 = self.vertices[tri.indices[1]].normal;
        const n2 = self.vertices[tri.indices[2]].normal;
        const shading_n = Vec3.normalize(
            Vec3.add(Vec3.add(Vec3.scale(n0, w), Vec3.scale(n1, u)), Vec3.scale(n2, v)),
        );

        const uv0 = self.vertices[tri.indices[0]].uv;
        const uv1 = self.vertices[tri.indices[1]].uv;
        const uv2 = self.vertices[tri.indices[2]].uv;
        const uv = [2]f32{
            w * uv0[0] + u * uv1[0] + v * uv2[0],
            w * uv0[1] + u * uv1[1] + v * uv2[1],
        };

        // Sign check on unnormalized cross product — same result, saves one @sqrt.
        const cross_e1e2 = Vec3.cross(e1, e2);
        const front_face = Vec3.dot(ray.direction, cross_e1e2) < 0;
        const geom_n = Vec3.normalize(cross_e1e2);
        const normal = if (front_face) geom_n else Vec3.neg(geom_n);

        out.* = .{
            .t = t,
            .point = ray.at(t),
            .normal = normal,
            .shading_normal = if (front_face) shading_n else Vec3.neg(shading_n),
            .uv = uv,
            .material_index = self.material_index,
            .front_face = front_face,
        };
        return true;
    }

    // Fast t-only test for shadow rays — skips normal/UV computation.
    pub fn intersectT(self: TriangleMesh, ray: Ray, t_min: f32, t_max: f32) ?f32 {
        const inf = std.math.floatMax(f32);
        var closest = t_max;
        var hit = false;

        var i: u32 = 0;
        while (i < self.triangles.len) : (i += 4) {
            const count: u32 = @intCast(@min(4, self.triangles.len - i));
            const pack = TrianglePack.init(&self, i, count);
            const ts = intersectT4(pack, ray, t_min, closest);
            inline for (0..4) |lane| {
                if (lane < count) {
                    const t = ts[lane];
                    if (t < inf and t <= closest) {
                        closest = t;
                        hit = true;
                    }
                }
            }
        }
        return if (hit) closest else null;
    }

    fn intersectTriangleT(
        self: TriangleMesh,
        tri: Triangle,
        ray: Ray,
        t_min: f32,
        t_max: f32,
    ) ?f32 {
        const v0 = self.vertices[tri.indices[0]].position;
        const v1 = self.vertices[tri.indices[1]].position;
        const v2 = self.vertices[tri.indices[2]].position;
        const e1 = Vec3.sub(v1, v0);
        const e2 = Vec3.sub(v2, v0);
        const h = Vec3.cross(ray.direction, e2);
        const det = Vec3.dot(e1, h);
        if (@abs(det) < 1e-8) return null;
        const inv_det = 1.0 / det;
        const s = Vec3.sub(ray.origin, v0);
        const u = Vec3.dot(s, h) * inv_det;
        if (u < 0.0 or u > 1.0) return null;
        const q = Vec3.cross(s, e1);
        const v = Vec3.dot(ray.direction, q) * inv_det;
        if (v < 0.0 or u + v > 1.0) return null;
        const t = Vec3.dot(e2, q) * inv_det;
        if (t < t_min or t > t_max) return null;
        return t;
    }

    pub fn bbox(self: TriangleMesh) AABB {
        return self.bounds;
    }

    pub fn sampleSurface(self: TriangleMesh, rng: [2]f32) SurfaceSample {
        // TODO: sample proportional to triangle area
        _ = self;
        _ = rng;
        return .{ .point = Vec3.zero(), .normal = Vec3.init(0, 1, 0), .uv = .{ 0, 0 }, .pdf = 0 };
    }

    pub fn area(self: TriangleMesh) f32 {
        // TODO: precompute total surface area
        _ = self;
        return 0;
    }

    // Build from flat OBJ-style arrays.  `indices` is laid out as N groups of 3
    // values (pos_idx, norm_idx, uv_idx) per vertex; every 3 vertices is one triangle.
    pub fn initFromArrays(
        alloc: std.mem.Allocator,
        positions: []const Vec3,
        normals: []const Vec3,
        uvs: []const [2]f32,
        indices: []const u32,
        material_index: u32,
    ) !TriangleMesh {
        const n_face_verts = indices.len / 3;
        const n_tris = n_face_verts / 3;

        var verts = try std.ArrayList(Vertex).initCapacity(alloc, n_face_verts);
        errdefer verts.deinit(alloc);
        var tris = try std.ArrayList(Triangle).initCapacity(alloc, n_tris);
        errdefer tris.deinit(alloc);

        const Key = struct { pi: u32, ni: u32, uvi: u32 };
        var vmap = std.AutoHashMap(Key, u32).init(alloc);
        defer vmap.deinit();

        var bounds = AABB.empty();

        for (0..n_tris) |fi| {
            var tri: Triangle = undefined;
            for (0..3) |vi| {
                const base = (fi * 3 + vi) * 3;
                const key = Key{
                    .pi  = indices[base + 0],
                    .ni  = indices[base + 1],
                    .uvi = indices[base + 2],
                };
                const gop = try vmap.getOrPut(key);
                if (!gop.found_existing) {
                    gop.value_ptr.* = @intCast(verts.items.len);
                    const pos = positions[key.pi];
                    bounds = bounds.expandPoint(pos);
                    try verts.append(alloc, .{
                        .position = pos,
                        .normal   = if (key.ni < normals.len) normals[key.ni] else Vec3.init(0, 1, 0),
                        .uv       = if (key.uvi < uvs.len) uvs[key.uvi] else .{ 0, 0 },
                    });
                }
                tri.indices[vi] = gop.value_ptr.*;
            }
            try tris.append(alloc, tri);
        }

        return TriangleMesh{
            .vertices      = try verts.toOwnedSlice(alloc),
            .triangles     = try tris.toOwnedSlice(alloc),
            .material_index = material_index,
            .bounds        = bounds,
        };
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "intersectT4: single triangle hit matches scalar" {
    // Triangle in the XY plane: v0=(0,0,0), v1=(1,0,0), v2=(0,1,0).
    // Ray from (0.25, 0.25, 2) pointing -Z should hit at t=2.
    const up = Vec3.init(0, 1, 0);
    const verts = [_]Vertex{
        .{ .position = Vec3.init(0, 0, 0), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(1, 0, 0), .normal = up, .uv = .{ 1, 0 } },
        .{ .position = Vec3.init(0, 1, 0), .normal = up, .uv = .{ 0, 1 } },
    };
    const tris = [_]Triangle{
        .{ .indices = .{ 0, 1, 2 } },
    };
    const mesh = TriangleMesh{
        .vertices = &verts,
        .triangles = &tris,
        .material_index = 0,
        .bounds = AABB.fromPoints(Vec3.init(0, 0, 0), Vec3.init(1, 1, 0)),
    };

    const ray = Ray.init(Vec3.init(0.25, 0.25, 2), Vec3.init(0, 0, -1));

    // Scalar result.
    const scalar_t = mesh.intersectT(ray, 0, std.math.floatMax(f32));
    try std.testing.expect(scalar_t != null);
    try std.testing.expectApproxEqAbs(scalar_t.?, 2.0, 1e-5);

    // SIMD result via TrianglePack.
    const pack = TrianglePack.init(&mesh, 0, 1);
    const ts = intersectT4(pack, ray, 0, std.math.floatMax(f32));
    try std.testing.expectApproxEqAbs(ts[0], 2.0, 1e-5);
    // Padding lanes must be misses.
    const inf = std.math.floatMax(f32);
    try std.testing.expectEqual(inf, ts[1]);
    try std.testing.expectEqual(inf, ts[2]);
    try std.testing.expectEqual(inf, ts[3]);
}

test "intersectT4: 4 triangles, ray hits only one" {
    // Four triangles at different depths; ray hits only the third.
    const up = Vec3.init(0, 1, 0);
    // Each triangle straddles the XY plane at a different Z.
    const verts = [_]Vertex{
        // tri 0 at z=10 — ray passes through but origin=0, dir=+Z, so ray misses (tri faces -Z)
        // Actually let's place them so only tri index 2 is in the ray's path.
        // Use triangles offset in X so only one is hit.
        // tri0: centred at x=-5 (miss)
        .{ .position = Vec3.init(-6, -1, 5), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(-4, -1, 5), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(-5,  1, 5), .normal = up, .uv = .{ 0, 0 } },
        // tri1: centred at x=-3 (miss)
        .{ .position = Vec3.init(-4, -1, 4), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(-2, -1, 4), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(-3,  1, 4), .normal = up, .uv = .{ 0, 0 } },
        // tri2: centred at x=0 (hit at t=3)
        .{ .position = Vec3.init(-1, -1, 3), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init( 1, -1, 3), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init( 0,  1, 3), .normal = up, .uv = .{ 0, 0 } },
        // tri3: centred at x=5 (miss)
        .{ .position = Vec3.init(4, -1, 2), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(6, -1, 2), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(5,  1, 2), .normal = up, .uv = .{ 0, 0 } },
    };
    const tris = [_]Triangle{
        .{ .indices = .{ 0,  1,  2 } },
        .{ .indices = .{ 3,  4,  5 } },
        .{ .indices = .{ 6,  7,  8 } },
        .{ .indices = .{ 9, 10, 11 } },
    };
    const mesh = TriangleMesh{
        .vertices = &verts,
        .triangles = &tris,
        .material_index = 0,
        .bounds = AABB.empty(),
    };

    const ray = Ray.initNormalized(Vec3.init(0, 0, 0), Vec3.init(0, 0, 1));
    const pack = TrianglePack.init(&mesh, 0, 4);
    const ts = intersectT4(pack, ray, 0, std.math.floatMax(f32));

    const inf = std.math.floatMax(f32);
    try std.testing.expectEqual(inf, ts[0]); // miss
    try std.testing.expectEqual(inf, ts[1]); // miss
    try std.testing.expectApproxEqAbs(ts[2], 3.0, 1e-5); // hit at t=3
    try std.testing.expectEqual(inf, ts[3]); // miss
}

test "intersect4 HitRecord matches scalar intersect" {
    const up = Vec3.init(0, 1, 0);
    const verts = [_]Vertex{
        .{ .position = Vec3.init(0, 0, 0), .normal = up, .uv = .{ 0, 0 } },
        .{ .position = Vec3.init(1, 0, 0), .normal = up, .uv = .{ 1, 0 } },
        .{ .position = Vec3.init(0, 1, 0), .normal = up, .uv = .{ 0, 1 } },
    };
    const tris = [_]Triangle{
        .{ .indices = .{ 0, 1, 2 } },
    };
    const mesh = TriangleMesh{
        .vertices = &verts,
        .triangles = &tris,
        .material_index = 0,
        .bounds = AABB.fromPoints(Vec3.init(0, 0, 0), Vec3.init(1, 1, 0)),
    };

    const ray = Ray.init(Vec3.init(0.25, 0.25, 2), Vec3.init(0, 0, -1));

    var scalar_out: HitRecord = undefined;
    const scalar_hit = mesh.intersect(ray, 0, std.math.floatMax(f32), &scalar_out);
    try std.testing.expect(scalar_hit);

    const pack = TrianglePack.init(&mesh, 0, 1);
    var simd_out: HitRecord = undefined;
    const simd_hit = intersect4(pack, &mesh, 0, 1, ray, 0, std.math.floatMax(f32), &simd_out);
    try std.testing.expect(simd_hit);

    try std.testing.expectApproxEqAbs(simd_out.t, scalar_out.t, 1e-5);
}
