const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const scene_mod = @import("scene");
const Scene = scene_mod.Scene;
const SceneLoader = scene_mod.SceneLoader;
const integrator_mod = @import("integrator");
const Integrator = integrator_mod.Integrator;
const PathTracer = integrator_mod.PathTracer;
const DebugView = integrator_mod.DebugView;
const PathRecord = integrator_mod.PathRecord;
const sampler_mod = @import("sampler");
const Sampler = sampler_mod.Sampler;
const film_mod = @import("film");
const Film = film_mod.Film;
const Tonemap = film_mod.Tonemap;
const viz_mod = @import("viz");
const PathViz = viz_mod.PathViz;
const perf = @import("test/perf.zig");
const build_options = @import("build_options");
const have_sdl2 = build_options.interactive;

const Mode = enum { render, interactive, debug };

const Config = struct {
    mode: Mode = .render,
    scene_path: ?[]const u8 = null,
    output_path: []const u8 = "out.png",
    width: u32 = 800,
    height: u32 = 600,
    spp: u32 = 64,
    max_depth: u32 = 8,
    tonemap: Tonemap = .aces,
    integrator: enum { path, direct, debug } = .path,
    debug_mode: DebugView.DebugMode = .normals,
    viz_paths: bool = false,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const cfg = try parseArgs(alloc);

    var scene = if (cfg.scene_path) |p|
        try SceneLoader.loadJson(alloc, p)
    else
        try SceneLoader.cornellBox(alloc);
    defer scene.deinit();

    var film = try Film.init(alloc, cfg.width, cfg.height);
    defer film.deinit();

    const integrator = makeIntegrator(cfg);

    switch (cfg.mode) {
        .render, .debug => try renderOffline(alloc, &scene, &film, integrator, cfg),
        .interactive => {
            if (!have_sdl2) {
                std.log.err("interactive mode requires -Dinteractive=true at build time (needs SDL2)", .{});
                return error.SdlNotEnabled;
            }
            try runInteractive(alloc, &scene, &film, integrator, cfg);
        },
    }

    try film.writePng(cfg.output_path, cfg.tonemap);
    std.log.info("wrote {s}", .{cfg.output_path});
}

fn makeIntegrator(cfg: Config) Integrator {
    return switch (cfg.integrator) {
        .path => .{ .path_tracer = .{ .max_depth = cfg.max_depth, .rr_depth = 3 } },
        .direct => .{ .direct = .{} },
        .debug => .{ .debug = .{ .mode = cfg.debug_mode } },
    };
}

fn renderOffline(
    alloc: std.mem.Allocator,
    scene: *const Scene,
    film: *Film,
    integrator: Integrator,
    cfg: Config,
) !void {
    perf.global.start();
    var path_viz = PathViz.init(alloc, 256);
    defer path_viz.deinit();

    for (0..cfg.spp) |spp_idx| {
        for (0..cfg.height) |row| {
            for (0..cfg.width) |col| {
                var sampler = Sampler{ .independent = sampler_mod.Independent.init(0) };
                sampler.startPixel(@intCast(col), @intCast(row), @intCast(spp_idx));

                const px = (@as(f32, @floatFromInt(col)) + sampler.next1d()) / @as(f32, @floatFromInt(cfg.width));
                const py = (@as(f32, @floatFromInt(row)) + sampler.next1d()) / @as(f32, @floatFromInt(cfg.height));
                const ray = scene.camera.generateRay(px, py, sampler.next2d());
                perf.global.addRay();

                const value = if (cfg.viz_paths) blk: {
                    var rec = PathRecord.init(alloc);
                    defer rec.deinit();
                    const v = integrator.liRecord(ray, scene, &sampler, alloc, &rec);
                    try path_viz.addRecord(rec);
                    break :blk v;
                } else integrator.li(ray, scene, &sampler, alloc);

                film.addSample(@intCast(col), @intCast(row), value);
                perf.global.addSamples(1);
            }
        }
        if (spp_idx % 8 == 0) {
            std.log.info("spp {}/{}", .{ spp_idx + 1, cfg.spp });
        }
    }

    if (cfg.viz_paths) path_viz.overlayOnFilm(film, scene.camera);

    const stdout = std.io.getStdOut().writer();
    try perf.global.report(stdout);
}

fn runInteractive(
    alloc: std.mem.Allocator,
    scene: *Scene,
    film: *Film,
    integrator: Integrator,
    cfg: Config,
) !void {
    const display = @import("display/sdl2.zig");
    var disp = try display.Display.init(alloc, "toyRender", cfg.width, cfg.height);
    defer disp.deinit();

    var spp: u32 = 0;
    var running = true;

    while (running) {
        while (disp.pollEvent()) |ev| {
            switch (ev) {
                .quit => running = false,
                .key_press => |key| handleKey(key, scene, film, &spp),
                .mouse_drag => |_| {
                    // TODO: orbit camera around scene center
                    film.clear();
                    spp = 0;
                },
                .mouse_scroll => |_| {
                    // TODO: dolly zoom
                    film.clear();
                    spp = 0;
                },
            }
        }

        // Render one sample per pixel per frame for progressive display.
        if (spp < cfg.spp) {
            for (0..cfg.height) |row| {
                for (0..cfg.width) |col| {
                    var sampler = Sampler{ .halton = .{ .index = spp, .pixel_offset = 0 } };
                    sampler.startPixel(@intCast(col), @intCast(row), spp);
                    const px = @as(f32, @floatFromInt(col)) / @as(f32, @floatFromInt(cfg.width));
                    const py = @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(cfg.height));
                    const ray = scene.camera.generateRay(px, py, sampler.next2d());
                    film.addSample(@intCast(col), @intCast(row), integrator.li(ray, scene, &sampler, alloc));
                }
            }
            spp += 1;
        }

        disp.update(film, cfg.tonemap);
        std.time.sleep(16 * std.time.ns_per_ms); // ~60 fps cap
    }
}

fn handleKey(key: u32, scene: *Scene, film: *Film, spp: *u32) void {
    _ = scene;
    const SDLK_r = 114; // 'r'
    switch (key) {
        SDLK_r => { film.clear(); spp.* = 0; }, // reset accumulation
        else => {},
    }
}

fn parseArgs(alloc: std.mem.Allocator) !Config {
    _ = alloc;
    // TODO: use std.process.argsAlloc + a proper argument parser
    // For now, return defaults.
    return .{};
}
