const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const film_mod = @import("film");
const Film = film_mod.Film;
const material_mod = @import("material");
const BxdfLobe = material_mod.BxdfLobe;
const scene_mod = @import("scene");
const Camera = scene_mod.Camera;
const integrator_mod = @import("integrator");
const PathRecord = integrator_mod.PathRecord;
const PathSegment = integrator_mod.PathSegment;

fn lobeColor(lobe: BxdfLobe) Spectrum {
    return switch (lobe) {
        .diffuse => Spectrum.init(0.2, 0.6, 1.0),       // blue
        .specular_reflection => Spectrum.init(1.0, 1.0, 0.2), // yellow
        .specular_transmission => Spectrum.init(0.2, 1.0, 0.8), // cyan
        .glossy_reflection => Spectrum.init(1.0, 0.6, 0.2),    // orange
        .glossy_transmission => Spectrum.init(0.6, 1.0, 0.4),  // green
    };
}

pub const PathViz = struct {
    records: std.ArrayList(PathRecord),
    alloc: std.mem.Allocator,
    max_records: usize,

    pub fn init(alloc: std.mem.Allocator, max_records: usize) PathViz {
        return .{
            .records = .empty,
            .alloc = alloc,
            .max_records = max_records,
        };
    }

    pub fn deinit(self: *PathViz) void {
        for (self.records.items) |*r| r.deinit();
        self.records.deinit(self.alloc);
    }

    pub fn addRecord(self: *PathViz, record: PathRecord) !void {
        if (self.records.items.len >= self.max_records) return;
        try self.records.append(self.alloc, record);
    }

    // Rasterize path segments as colored lines onto the film.
    // Each segment is stepped along in world space and projected.
    pub fn overlayOnFilm(self: *const PathViz, film: *Film, camera: Camera) void {
        for (self.records.items) |*rec| {
            for (rec.segments.items) |seg| {
                drawSegment(film, camera, seg);
            }
        }
    }

    fn drawSegment(film: *Film, camera: Camera, seg: PathSegment) void {
        const color = lobeColor(seg.lobe);
        const steps = 32;
        var i: u32 = 0;
        while (i <= steps) : (i += 1) {
            const t = seg.length * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            const world_pt = Vec3.add(seg.origin, Vec3.scale(seg.direction, t));
            if (projectToFilm(film, camera, world_pt)) |px| {
                film.addSample(px[0], px[1], color);
            }
        }
    }

    fn projectToFilm(film: *Film, camera: Camera, world_pt: Vec3) ?[2]u32 {
        // TODO: proper world→NDC→raster transform using camera matrices
        _ = film;
        _ = camera;
        _ = world_pt;
        return null;
    }
};
