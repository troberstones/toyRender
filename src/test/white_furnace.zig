// White furnace test: a material in a uniform white environment must not
// gain or lose energy. Integrate f(wo,wi)*cos(theta) over the hemisphere
// and verify the result is ≤ 1 for any wo.
const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Spectrum = math.Spectrum;
const material_mod = @import("material");
const Material = material_mod.Material;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;

const N_SAMPLES = 10_000;

fn makeFakeHit() HitRecord {
    return .{
        .t = 1.0,
        .point = Vec3.zero(),
        .normal = Vec3.init(0, 1, 0),
        .shading_normal = Vec3.init(0, 1, 0),
        .uv = .{ 0, 0 },
        .material_index = 0,
        .front_face = true,
    };
}

fn estimateAlbedo(mat: Material, wo: Vec3) f32 {
    var rng = std.Random.DefaultPrng.init(42);
    var random = rng.random();
    var sum: f32 = 0.0;
    var count: u32 = 0;
    const hit = makeFakeHit();

    var i: u32 = 0;
    while (i < N_SAMPLES) : (i += 1) {
        const r0 = random.float(f32);
        const r1 = random.float(f32);
        const s = mat.sample(wo, hit, .{ r0, r1 }) orelse continue;
        if (s.is_specular) continue;
        if (s.pdf < 1e-7) continue;
        const cos_theta = @abs(Vec3.dot(s.wi, hit.shading_normal));
        sum += s.f.luminance() * cos_theta / s.pdf;
        count += 1;
    }
    if (count == 0) return 0;
    return sum / @as(f32, @floatFromInt(count));
}

test "lambertian white furnace" {
    const mat = Material{ .lambertian = .{ .albedo = Spectrum.one() } };
    const wo = Vec3.normalize(Vec3.init(0.3, 0.7, 0.5));
    const albedo = estimateAlbedo(mat, wo);
    // Lambertian with albedo=1 must integrate to exactly 1 on a hemisphere.
    try std.testing.expectApproxEqAbs(albedo, 1.0, 0.02);
}

test "ggx energy conservation" {
    const mat = Material{ .ggx = .{ .base_color = Spectrum.one(), .roughness = 0.5, .metallic = 1.0 } };
    const wo = Vec3.normalize(Vec3.init(0.3, 0.7, 0.5));
    const albedo = estimateAlbedo(mat, wo);
    // GGX must not produce more energy than it receives.
    try std.testing.expect(albedo <= 1.05); // 5% tolerance for Monte Carlo noise
}
