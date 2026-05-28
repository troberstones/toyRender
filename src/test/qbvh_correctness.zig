// QBVH correctness test: renders the Cornell box scene twice — once with QBVH
// (built by collapsing a binary BVH) and once with the binary BVH directly —
// and asserts pixel values match within tolerance.
//
// Because the Independent sampler is seeded per-pixel via startPixel(col, row,
// spp_idx), both renders follow exactly the same random sequence for every
// pixel.  Both structures represent the same scene geometry, so hit records
// must match.
const std = @import("std");
const math = @import("math");
const Spectrum = math.Spectrum;
const scene_mod = @import("scene");
const SceneLoader = scene_mod.SceneLoader;
const accel_mod = @import("accel");
const Bvh = accel_mod.Bvh;
const Qbvh = accel_mod.Qbvh;
const sampler_mod = @import("sampler");
const Sampler = sampler_mod.Sampler;
const film_mod = @import("film");
const Film = film_mod.Film;
const integrator_mod = @import("integrator");
const Integrator = integrator_mod.Integrator;

const WIDTH: u32 = 64;
const HEIGHT: u32 = 64;
const SPP: u32 = 4;

fn renderScene(
    scene: *const scene_mod.Scene,
    film: *Film,
    alloc: std.mem.Allocator,
) void {
    const integrator = Integrator{ .path_tracer = .{ .max_depth = 4, .rr_depth = 3 } };
    var sampler = Sampler{ .independent = .init(42) };

    for (0..HEIGHT) |row| {
        for (0..WIDTH) |col| {
            for (0..SPP) |spp_idx| {
                sampler.startPixel(@intCast(col), @intCast(row), @intCast(spp_idx));

                const uv = sampler.next2d();
                const px = (@as(f32, @floatFromInt(col)) + uv[0]) / @as(f32, @floatFromInt(WIDTH));
                const py = (@as(f32, @floatFromInt(row)) + uv[1]) / @as(f32, @floatFromInt(HEIGHT));

                const ray_uv = sampler.next2d();
                const ray = scene.camera.generateRay(px, py, ray_uv);
                const li = integrator.li(ray, scene, &sampler, alloc);
                film.addSample(@intCast(col), @intCast(row), li);
            }
        }
    }
}

test "qbvh and binary bvh produce identical output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // --- QBVH render (cornellBox() uses QBVH by default) ---
    var qbvh_scene = try SceneLoader.cornellBox(alloc);
    defer qbvh_scene.deinit();

    var qbvh_film = try Film.init(alloc, WIDTH, HEIGHT);
    defer qbvh_film.deinit();

    renderScene(&qbvh_scene, &qbvh_film, alloc);

    // --- Binary BVH render (build separately and swap the accel) ---
    var bvh_scene = try SceneLoader.cornellBox(alloc);
    // Free the QBVH that cornellBox() built and replace with a binary BVH.
    bvh_scene.accel.deinit(alloc);

    const refs = try alloc.alloc(accel_mod.InstanceRef, bvh_scene.instances.len);
    for (bvh_scene.instances, refs) |*inst, *ref| {
        ref.* = inst.toRef();
    }
    const bvh = try Bvh.build(alloc, refs);
    bvh_scene.accel = .{ .bvh = bvh };

    var bvh_film = try Film.init(alloc, WIDTH, HEIGHT);
    defer bvh_film.deinit();

    renderScene(&bvh_scene, &bvh_film, alloc);
    bvh_scene.deinit();

    // --- Compare films ---
    const tolerance: f32 = 1e-4;

    for (0..HEIGHT) |row| {
        for (0..WIDTH) |col| {
            const qbvh_px = qbvh_film.getPixelAvg(@intCast(col), @intCast(row));
            const bvh_px = bvh_film.getPixelAvg(@intCast(col), @intCast(row));

            try std.testing.expectApproxEqAbs(qbvh_px.r, bvh_px.r, tolerance);
            try std.testing.expectApproxEqAbs(qbvh_px.g, bvh_px.g, tolerance);
            try std.testing.expectApproxEqAbs(qbvh_px.b, bvh_px.b, tolerance);
        }
    }
}
