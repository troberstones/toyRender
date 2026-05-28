const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --- Modules (ordered by dependency depth) ---

    const perf_mod = b.addModule("perf", .{
        .root_source_file = b.path("src/test/perf.zig"),
    });

    const math_mod = b.addModule("math", .{
        .root_source_file = b.path("src/math/root.zig"),
    });

    const geometry_mod = b.addModule("geometry", .{
        .root_source_file = b.path("src/geometry/root.zig"),
        .imports = &.{.{ .name = "math", .module = math_mod }},
    });

    const accel_mod = b.addModule("accel", .{
        .root_source_file = b.path("src/accel/root.zig"),
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "geometry", .module = geometry_mod },
        },
    });

    const material_mod = b.addModule("material", .{
        .root_source_file = b.path("src/material/root.zig"),
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "geometry", .module = geometry_mod },
        },
    });

    const light_mod = b.addModule("light", .{
        .root_source_file = b.path("src/light/root.zig"),
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "geometry", .module = geometry_mod },
        },
    });

    const sampler_mod = b.addModule("sampler", .{
        .root_source_file = b.path("src/sampler/root.zig"),
        .imports = &.{.{ .name = "math", .module = math_mod }},
    });

    const film_mod = b.addModule("film", .{
        .root_source_file = b.path("src/film/root.zig"),
        .imports = &.{.{ .name = "math", .module = math_mod }},
    });

    const scene_mod = b.addModule("scene", .{
        .root_source_file = b.path("src/scene/root.zig"),
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "geometry", .module = geometry_mod },
            .{ .name = "accel", .module = accel_mod },
            .{ .name = "material", .module = material_mod },
            .{ .name = "light", .module = light_mod },
            .{ .name = "perf", .module = perf_mod },
        },
    });

    const integrator_mod = b.addModule("integrator", .{
        .root_source_file = b.path("src/integrator/root.zig"),
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "scene", .module = scene_mod },
            .{ .name = "material", .module = material_mod },
            .{ .name = "light", .module = light_mod },
            .{ .name = "sampler", .module = sampler_mod },
            .{ .name = "film", .module = film_mod },
        },
    });

    const viz_mod = b.addModule("viz", .{
        .root_source_file = b.path("src/viz/root.zig"),
        .imports = &.{
            .{ .name = "math", .module = math_mod },
            .{ .name = "film", .module = film_mod },
            .{ .name = "material", .module = material_mod },
            .{ .name = "scene", .module = scene_mod },
            .{ .name = "integrator", .module = integrator_mod },
        },
    });

    // -Dinteractive=true  enables the SDL2 display (requires libSDL2-dev)
    const interactive = b.option(bool, "interactive", "Enable SDL2 interactive display") orelse false;

    // --- Executable ---
    const exe = b.addExecutable(.{
        .name = "toyRender",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("perf", perf_mod);
    exe.root_module.addImport("math", math_mod);
    exe.root_module.addImport("geometry", geometry_mod);
    exe.root_module.addImport("accel", accel_mod);
    exe.root_module.addImport("material", material_mod);
    exe.root_module.addImport("light", light_mod);
    exe.root_module.addImport("sampler", sampler_mod);
    exe.root_module.addImport("film", film_mod);
    exe.root_module.addImport("scene", scene_mod);
    exe.root_module.addImport("integrator", integrator_mod);
    exe.root_module.addImport("viz", viz_mod);
    const options = b.addOptions();
    options.addOption(bool, "interactive", interactive);
    exe.root_module.addOptions("build_options", options);
    if (interactive) {
        exe.root_module.linkSystemLibrary("SDL2", .{});
        exe.root_module.link_libc = true;
        // Compile the SDL2 C shim with system headers (avoids Zig's bundled
        // arm_neon.h which has ARM builtins Zig 0.16's translate-c can't handle).
        exe.root_module.addCSourceFile(.{
            .file = b.path("src/display/sdl2_bind.c"),
            .flags = &.{"-I/opt/homebrew/include"},
        });
    }
    b.installArtifact(exe);

    // --- Run step ---
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the renderer");
    run_step.dependOn(&run_cmd.step);

    // --- Test step ---
    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unit_tests.root_module.addImport("math", math_mod);
    unit_tests.root_module.addImport("geometry", geometry_mod);
    unit_tests.root_module.addImport("accel", accel_mod);
    unit_tests.root_module.addImport("material", material_mod);
    unit_tests.root_module.addImport("scene", scene_mod);
    unit_tests.root_module.addImport("sampler", sampler_mod);
    unit_tests.root_module.addImport("film", film_mod);
    unit_tests.root_module.addImport("integrator", integrator_mod);
    unit_tests.root_module.addImport("perf", perf_mod);
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
