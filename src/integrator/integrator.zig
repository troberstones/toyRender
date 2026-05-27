const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const Ray = math.Ray;
const material_mod = @import("material");
const BxdfLobe = material_mod.BxdfLobe;
const Scene = @import("scene").Scene;
const sampler_mod = @import("sampler");
const Sampler = sampler_mod.Sampler;
const film_mod = @import("film");
const Film = film_mod.Film;

const PathTracer = @import("path_tracer.zig").PathTracer;
const DirectLighting = @import("direct.zig").DirectLighting;
const DebugView = @import("debug.zig").DebugView;

pub const PathSegment = struct {
    origin: Vec3,
    direction: Vec3,
    length: f32,
    lobe: BxdfLobe,
    depth: u8,
    throughput: Spectrum,
};

pub const PathRecord = struct {
    segments: std.ArrayList(PathSegment),
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator) PathRecord {
        return .{ .segments = .empty, .alloc = alloc };
    }

    pub fn deinit(self: *PathRecord) void {
        self.segments.deinit(self.alloc);
    }

    pub fn reset(self: *PathRecord) void {
        self.segments.clearRetainingCapacity();
    }
};

// Each variant must implement:
//   fn li(self, ray: Ray, scene: *const Scene, sampler: *Sampler, alloc: std.mem.Allocator) Spectrum
//   fn liRecord(self, ray: Ray, scene: *const Scene, sampler: *Sampler, alloc: std.mem.Allocator, record: *PathRecord) Spectrum
pub const Integrator = union(enum) {
    path_tracer: PathTracer,
    direct: DirectLighting,
    debug: DebugView,

    pub fn li(
        self: Integrator,
        ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        alloc: std.mem.Allocator,
    ) Spectrum {
        return switch (self) {
            inline else => |ig| ig.li(ray, scene, sampler, alloc),
        };
    }

    pub fn liRecord(
        self: Integrator,
        ray: Ray,
        scene: *const Scene,
        sampler: *Sampler,
        alloc: std.mem.Allocator,
        record: *PathRecord,
    ) Spectrum {
        return switch (self) {
            inline else => |ig| ig.liRecord(ray, scene, sampler, alloc, record),
        };
    }
};
