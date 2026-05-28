// BVH correctness test: renders the Cornell box scene twice — once with BVH
// and once with BruteForce — and asserts pixel-identical results.
//
// Because the Independent sampler is seeded per-pixel via startPixel(col, row,
// spp_idx), both renders follow exactly the same random sequence for every
// pixel.  The only difference is the acceleration structure traversal order,
// which must produce the same hit records (both are correct nearest-hit
// searches).  Therefore the two films should be bit-for-bit identical.
const std = @import("std");
const math = @import("math");
const Spectrum = math.Spectrum;
const scene_mod = @import("scene");
const SceneLoader = scene_mod.SceneLoader;
const accel_mod = @import("accel");
const BruteForce = accel_mod.BruteForce;
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

                // Sub-pixel offset via sampler for anti-aliasing.
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

test "bvh and brute-force produce identical output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // --- BVH render ---
    var bvh_scene = try SceneLoader.cornellBox(alloc);
    defer bvh_scene.deinit();

    var bvh_film = try Film.init(alloc, WIDTH, HEIGHT);
    defer bvh_film.deinit();

    renderScene(&bvh_scene, &bvh_film, alloc);

    // --- BruteForce render ---
    // Build a second Cornell box scene, then swap the accel structure.
    var bf_scene = try SceneLoader.cornellBox(alloc);
    // Free the BVH that cornellBox() built — we will replace it.
    bf_scene.accel.deinit(alloc);

    // Build an InstanceRef slice pointing at the new scene's instances.
    const refs = try alloc.alloc(accel_mod.InstanceRef, bf_scene.instances.len);
    for (bf_scene.instances, refs) |*inst, *ref| {
        ref.* = inst.toRef();
    }
    bf_scene.accel = .{ .brute_force = BruteForce{ .instances = refs } };

    var bf_film = try Film.init(alloc, WIDTH, HEIGHT);
    defer bf_film.deinit();

    renderScene(&bf_scene, &bf_film, alloc);
    bf_scene.deinit();

    // --- Compare films ---
    // The sampler is re-seeded identically per pixel, so results must match
    // exactly (same float operations, same traversal order for each sample).
    // We use a small tolerance to guard against any future refactor that
    // changes operation order without changing correctness.
    const tolerance: f32 = 1e-4;

    for (0..HEIGHT) |row| {
        for (0..WIDTH) |col| {
            const bvh_px = bvh_film.getPixelAvg(@intCast(col), @intCast(row));
            const bf_px = bf_film.getPixelAvg(@intCast(col), @intCast(row));

            try std.testing.expectApproxEqAbs(bvh_px.r, bf_px.r, tolerance);
            try std.testing.expectApproxEqAbs(bvh_px.g, bf_px.g, tolerance);
            try std.testing.expectApproxEqAbs(bvh_px.b, bf_px.b, tolerance);
        }
    }
}
