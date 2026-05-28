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
const perf = @import("perf");
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
    threads: u32 = 0, // 0 = auto-detect via std.Thread.getCpuCount()
};

/// One 16×16 (or smaller at image boundary) tile of pixels.
const Tile = struct {
    x0: u32,
    y0: u32,
    x1: u32, // exclusive
    y1: u32, // exclusive
};

/// Context passed to each worker thread.
const WorkerCtx = struct {
    tiles: []const Tile,
    counter: *std.atomic.Value(u32),
    scene: *const Scene,
    film: *Film,
    integrator: Integrator,
    spp_idx: u32,
    cfg: *const Config,
};

fn workerFn(ctx: WorkerCtx) void {
    // Per-thread arena; reset after each tile to avoid unbounded growth.
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    // Per-thread sampler; startPixel fully re-seeds it each pixel, so the
    // initial payload value is irrelevant.
    var sampler = Sampler{ .independent = undefined };

    while (true) {
        const idx = ctx.counter.fetchAdd(1, .monotonic);
        if (idx >= ctx.tiles.len) break;

        const tile = ctx.tiles[idx];
        _ = arena.reset(.retain_capacity);
        const tile_alloc = arena.allocator();

        var row = tile.y0;
        while (row < tile.y1) : (row += 1) {
            var col = tile.x0;
            while (col < tile.x1) : (col += 1) {
                sampler.startPixel(col, row, ctx.spp_idx);

                const px = (@as(f32, @floatFromInt(col)) + sampler.next1d()) / @as(f32, @floatFromInt(ctx.cfg.width));
                const py = (@as(f32, @floatFromInt(row)) + sampler.next1d()) / @as(f32, @floatFromInt(ctx.cfg.height));
                const ray = ctx.scene.camera.generateRay(px, py, sampler.next2d());

                const value = ctx.integrator.li(ray, ctx.scene, &sampler, tile_alloc);
                ctx.film.addSample(col, row, value);
                perf.global.addSamples(1);
            }
        }
        // Flush thread-local ray counters once per tile — avoids per-ray atomic contention.
        perf.global.flushThreadLocal();
    }
}

pub fn main(init: std.process.Init.Minimal) !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const cfg = parseArgs(init.args);

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

    // Print a live progress line to stderr roughly once per second.
    var last_progress_ns: i128 = 0;

    // ------------------------------------------------------------------ tiles
    const tile_size: u32 = 16;
    const tiles_x = (cfg.width + tile_size - 1) / tile_size;
    const tiles_y = (cfg.height + tile_size - 1) / tile_size;
    const n_tiles = tiles_x * tiles_y;

    const tiles = try alloc.alloc(Tile, n_tiles);
    defer alloc.free(tiles);

    for (0..tiles_y) |ty| {
        for (0..tiles_x) |tx| {
            const x0: u32 = @intCast(tx * tile_size);
            const y0: u32 = @intCast(ty * tile_size);
            tiles[ty * tiles_x + tx] = .{
                .x0 = x0,
                .y0 = y0,
                .x1 = @min(x0 + tile_size, cfg.width),
                .y1 = @min(y0 + tile_size, cfg.height),
            };
        }
    }

    // ---------------------------------------------------------------- threads
    // viz_paths uses PathViz which is single-threaded, so fall back to 1 thread.
    const n_threads: u32 = if (cfg.viz_paths) 1 else
        if (cfg.threads != 0) cfg.threads
        else @intCast(std.Thread.getCpuCount() catch 4);

    var counter = std.atomic.Value(u32).init(0);

    for (0..cfg.spp) |spp_idx| {
        // Reset tile counter for this spp pass.
        counter.store(0, .seq_cst);

        if (n_threads <= 1 or cfg.viz_paths) {
            // ---- single-threaded path (supports viz_paths) ----
            var sampler = Sampler{ .independent = undefined };
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();

            for (tiles) |tile| {
                _ = arena.reset(.retain_capacity);
                const tile_alloc = arena.allocator();

                var row = tile.y0;
                while (row < tile.y1) : (row += 1) {
                    var col = tile.x0;
                    while (col < tile.x1) : (col += 1) {
                        sampler.startPixel(col, row, @intCast(spp_idx));

                        const px = (@as(f32, @floatFromInt(col)) + sampler.next1d()) / @as(f32, @floatFromInt(cfg.width));
                        const py = (@as(f32, @floatFromInt(row)) + sampler.next1d()) / @as(f32, @floatFromInt(cfg.height));
                        const ray = scene.camera.generateRay(px, py, sampler.next2d());

                        const value = if (cfg.viz_paths) blk: {
                            var rec = PathRecord.init(tile_alloc);
                            defer rec.deinit();
                            const v = integrator.liRecord(ray, scene, &sampler, tile_alloc, &rec);
                            try path_viz.addRecord(rec);
                            break :blk v;
                        } else integrator.li(ray, scene, &sampler, tile_alloc);

                        film.addSample(col, row, value);
                        perf.global.addSamples(1);
                    }
                }
                perf.global.flushThreadLocal();
            }
        } else {
            // ---- multi-threaded path ----
            const ctx = WorkerCtx{
                .tiles = tiles,
                .counter = &counter,
                .scene = scene,
                .film = film,
                .integrator = integrator,
                .spp_idx = @intCast(spp_idx),
                .cfg = &cfg,
            };

            const thread_list = try alloc.alloc(std.Thread, n_threads);
            defer alloc.free(thread_list);

            for (thread_list) |*t| {
                t.* = try std.Thread.spawn(.{}, workerFn, .{ctx});
            }
            for (thread_list) |t| t.join();
        }

        // Refresh the live Mrays/s line at most once per second.
        const now = perf.global.elapsedNs();
        if (now - last_progress_ns >= std.time.ns_per_s) {
            last_progress_ns = now;
            perf.global.printProgress(@intCast(spp_idx + 1), @intCast(cfg.spp));
        }
    }
    std.debug.print("\n", .{}); // finish the \r progress line

    if (cfg.viz_paths) path_viz.overlayOnFilm(film, scene.camera);

    var buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(std.Options.debug_io, &buf);
    try perf.global.report(&stdout_writer.interface);
    try stdout_writer.interface.flush();
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
                .mouse_drag => {
                    // TODO: orbit camera around scene center
                    film.clear();
                    spp = 0;
                },
                .mouse_scroll => {
                    // TODO: dolly zoom
                    film.clear();
                    spp = 0;
                },
            }
        }

        // Render one sample per pixel per frame for progressive display.
        if (spp < cfg.spp) {
            // One sampler reused across all pixels — startPixel fully reinitialises
            // both fields, so the initial value here is discarded immediately.
            var sampler = Sampler{ .halton = .{ .index = 0, .pixel_offset = 0 } };
            for (0..cfg.height) |row| {
                for (0..cfg.width) |col| {
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
        const ts = std.c.timespec{ .sec = 0, .nsec = 16 * std.time.ns_per_ms };
        _ = std.c.nanosleep(&ts, null); // ~60 fps cap
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

fn parseArgs(args: std.process.Args) Config {
    var cfg = Config{};
    var it = std.process.Args.Iterator.init(args);
    _ = it.skip(); // argv[0] is the program name

    while (it.next()) |arg| {
        if (eql(arg, "--help") or eql(arg, "-h")) {
            printUsage();
            std.process.exit(0);
        } else if (eql(arg, "--mode")) {
            const val = it.next() orelse std.process.fatal("--mode requires a value\n", .{});
            cfg.mode = std.meta.stringToEnum(Mode, val) orelse
                std.process.fatal("--mode: unknown value '{s}' (render|interactive|debug)\n", .{val});
        } else if (eql(arg, "--scene")) {
            cfg.scene_path = it.next() orelse std.process.fatal("--scene requires a path\n", .{});
        } else if (eql(arg, "--output") or eql(arg, "-o")) {
            cfg.output_path = it.next() orelse std.process.fatal("--output requires a path\n", .{});
        } else if (eql(arg, "--width")) {
            const val = it.next() orelse std.process.fatal("--width requires a value\n", .{});
            cfg.width = std.fmt.parseInt(u32, val, 10) catch
                std.process.fatal("--width: not a valid number\n", .{});
        } else if (eql(arg, "--height")) {
            const val = it.next() orelse std.process.fatal("--height requires a value\n", .{});
            cfg.height = std.fmt.parseInt(u32, val, 10) catch
                std.process.fatal("--height: not a valid number\n", .{});
        } else if (eql(arg, "--spp")) {
            const val = it.next() orelse std.process.fatal("--spp requires a value\n", .{});
            cfg.spp = std.fmt.parseInt(u32, val, 10) catch
                std.process.fatal("--spp: not a valid number\n", .{});
        } else if (eql(arg, "--depth")) {
            const val = it.next() orelse std.process.fatal("--depth requires a value\n", .{});
            cfg.max_depth = std.fmt.parseInt(u32, val, 10) catch
                std.process.fatal("--depth: not a valid number\n", .{});
        } else if (eql(arg, "--tonemap")) {
            const val = it.next() orelse std.process.fatal("--tonemap requires a value\n", .{});
            cfg.tonemap = if (eql(val, "linear")) .linear
                else if (eql(val, "reinhard")) .reinhard
                else if (eql(val, "aces")) .aces
                else std.process.fatal("--tonemap: unknown value '{s}' (linear|reinhard|aces)\n", .{val});
        } else if (eql(arg, "--integrator")) {
            const val = it.next() orelse std.process.fatal("--integrator requires a value\n", .{});
            cfg.integrator = std.meta.stringToEnum(@TypeOf(cfg.integrator), val) orelse
                std.process.fatal("--integrator: unknown value '{s}' (path|direct|debug)\n", .{val});
        } else if (eql(arg, "--debug-mode")) {
            const val = it.next() orelse std.process.fatal("--debug-mode requires a value\n", .{});
            cfg.debug_mode = std.meta.stringToEnum(DebugView.DebugMode, val) orelse
                std.process.fatal("--debug-mode: unknown value '{s}'\n", .{val});
        } else if (eql(arg, "--viz-paths")) {
            cfg.viz_paths = true;
        } else if (eql(arg, "--threads")) {
            const val = it.next() orelse std.process.fatal("--threads requires a value\n", .{});
            cfg.threads = std.fmt.parseInt(u32, val, 10) catch
                std.process.fatal("--threads: not a valid number\n", .{});
        } else {
            std.process.fatal("unknown argument '{s}' — try --help\n", .{arg});
        }
    }
    return cfg;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn printUsage() void {
    std.debug.print(
        \\Usage: toyRender [options]
        \\
        \\Options:
        \\  --mode <render|interactive|debug>   Render mode (default: render)
        \\  --scene <path>                      JSON scene file (default: Cornell box)
        \\  --output, -o <path>                 Output image (default: out.png)
        \\  --width <n>                         Image width  (default: 800)
        \\  --height <n>                        Image height (default: 600)
        \\  --spp <n>                           Samples per pixel (default: 64)
        \\  --depth <n>                         Max ray depth (default: 8)
        \\  --tonemap <linear|reinhard|aces>    Tone mapping (default: aces)
        \\  --integrator <path|direct|debug>    Integrator (default: path)
        \\  --debug-mode <normals|shading_normals|albedo|depth|uv|path_length>
        \\  --viz-paths                         Overlay path visualization
        \\  --threads <n>                       Worker threads (default: CPU count)
        \\  --help, -h                          Show this help
        \\
    , .{});
}
