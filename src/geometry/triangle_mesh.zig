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

pub const TriangleMesh = struct {
    vertices: []const Vertex,
    triangles: []const Triangle,
    material_index: u32,
    // Precomputed bounding box over all vertices.
    bounds: AABB,

    pub fn intersect(self: TriangleMesh, ray: Ray, t_min: f32, t_max: f32, out: *HitRecord) bool {
        var closest = t_max;
        var found = false;

        for (self.triangles) |tri| {
            if (intersectTriangle(self, tri, ray, t_min, closest, out)) {
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
        var closest = t_max;
        var hit = false;
        for (self.triangles) |tri| {
            if (intersectTriangleT(self, tri, ray, t_min, closest)) |t| {
                closest = t;
                hit = true;
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

    // Build from flat arrays — called by the .obj loader.
    pub fn initFromArrays(
        alloc: std.mem.Allocator,
        positions: []const Vec3,
        normals: []const Vec3,
        uvs: []const [2]f32,
        indices: []const u32, // triples: position, normal, uv per vertex
        material_index: u32,
    ) !TriangleMesh {
        _ = alloc;
        _ = positions;
        _ = normals;
        _ = uvs;
        _ = indices;
        _ = material_index;
        // TODO: deindex and build Vertex/Triangle arrays, compute bounds
        @panic("TriangleMesh.initFromArrays not yet implemented");
    }
};
