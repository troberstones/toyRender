# toyRender — Architecture & Task Tracker

## Overview

toyRender is a modular path-tracing test platform written in Zig (≥ 0.13). Its primary purpose is to serve as an experimental harness for comparing acceleration structures, geometry representations, and instancing models under a unified rendering framework.

The codebase is organized as a set of named Zig modules wired together in `build.zig`. Each module exposes a tagged-union interface so variants can be swapped at runtime without vtables or heap allocation.

---

## Module Dependency Graph

```
main
 ├── math          (no deps)
 ├── geometry      → math
 ├── accel         → math, geometry
 ├── material      → math, geometry
 ├── light         → math, geometry
 ├── sampler       → math
 ├── film          → math
 ├── scene         → math, geometry, accel, material, light
 ├── integrator    → math, scene, material, light, sampler, film
 └── viz           → math, film, material, scene
```

SDL2 and libC are linked directly into the executable (not a module).

---

## Modules

### `math`  `src/math/`

Foundation types used everywhere. Fully implemented.

| File | Contents |
|---|---|
| `vec3.zig` | `Vec3` — add/sub/scale/dot/cross/normalize/reflect/refract/lerp/toWorld |
| `mat4.zig` | `Mat4` — column-major; translate/scale/rotateXYZ/mul/transformPoint/transformDirection/transformNormal; **inverse stubbed** |
| `ray.zig` | `Ray` — origin, direction (normalized), t_min/t_max |
| `bbox.zig` | `AABB` — slab intersection, expand, centroid, surfaceArea, longestAxis |
| `spectrum.zig` | `Spectrum` (RGB f32) — add/mul/scale/luminance/lerp/clampNeg |

### `geometry`  `src/geometry/`

Defines the `Geometry` tagged-union interface and concrete primitives.

```zig
pub const Geometry = union(enum) {
    triangle_mesh: TriangleMesh,
    sphere: Sphere,
    plane: Plane,
    // fn intersect, bbox, sampleSurface, area
};
```

| File | Status |
|---|---|
| `geometry.zig` | `HitRecord`, `SurfaceSample`, `Geometry` interface — **done** |
| `analytic.zig` | `Sphere` (full: intersect, bbox, uniform surface sampling), `Plane` (intersect done, finite-extent bbox/sampling stubbed) |
| `triangle_mesh.zig` | `TriangleMesh` — Möller–Trumbore per-triangle intersection, normal/UV interpolation, bounds; `initFromArrays` **stubbed** |

**`HitRecord` fields**

| Field | Type | Notes |
|---|---|---|
| `t` | f32 | Ray parameter at hit |
| `point` | Vec3 | World-space hit point |
| `normal` | Vec3 | Geometric normal, faces away from ray |
| `shading_normal` | Vec3 | Interpolated vertex normal |
| `uv` | [2]f32 | Texture coordinates |
| `material_index` | u32 | Index into `Scene.materials` |
| `front_face` | bool | True when ray hits front face |

### `accel`  `src/accel/`

Pluggable acceleration structure. The `InstanceRef` type decouples the accel module from the scene module (avoids a circular dependency).

```zig
pub const AccelStructure = union(enum) {
    brute_force: BruteForce,
    bvh: Bvh,
    // fn intersect(*Self, Ray) ?HitRecord
    // fn intersectAny(*Self, Ray, max_t: f32) bool
};
```

| File | Status |
|---|---|
| `instance_ref.zig` | `InstanceRef` — opaque pointer + function pointer; bridges scene→accel — **done** |
| `brute_force.zig` | Linear scan over all instances — **done** |
| `bvh.zig` | SAH BVH — node/primitive storage defined; **build and traversal stubbed** |

### `material`  `src/material/`

BxDF interface. All variants are delta or smooth; the integrator uses `is_specular` to skip MIS weighting.

```zig
pub const Material = union(enum) {
    lambertian: Lambertian,
    specular:   Specular,
    ggx:        Ggx,
    dielectric: Dielectric,
    // fn eval(wo, wi, hit) Spectrum
    // fn sample(wo, hit, rng) ?BxdfSample
    // fn pdf(wo, wi, hit) f32
    // fn emission() Spectrum
};
```

| File | Status |
|---|---|
| `lambertian.zig` | Cosine-weighted hemisphere sampling — **done** |
| `specular.zig` | Perfect mirror (delta) — **done** |
| `ggx.zig` | GGX microfacet (D, G, F); NDF sampling stubbed with basic spherical; **VNDF sampling (Heitz 2018) TODO** |
| `dielectric.zig` | Fresnel-Schlick reflection/refraction split — **done** |

**`BxdfSample` fields**

| Field | Type | Notes |
|---|---|---|
| `wi` | Vec3 | Sampled incident direction |
| `f` | Spectrum | BxDF value f(wo, wi) |
| `pdf` | f32 | Sampling PDF |
| `lobe` | `BxdfLobe` | Used by path visualizer to color segments |
| `is_specular` | bool | True for delta distributions — skip MIS |

**`BxdfLobe` values:** `diffuse`, `specular_reflection`, `specular_transmission`, `glossy_reflection`, `glossy_transmission`

### `light`  `src/light/`

```zig
pub const Light = union(enum) {
    point: PointLight,
    area:  AreaLight,
    env:   EnvLight,
    // fn sampleLi(hit_point, rng) ?LightSample
    // fn pdfLi(hit_point, wi) f32
    // fn le(ray) Spectrum
    // fn isDelta() bool
};
```

| File | Status |
|---|---|
| `point_light.zig` | Inverse-square falloff, delta — **done** |
| `area_light.zig` | References emissive instance by index; sampling and solid-angle PDF **stubbed** |
| `env_light.zig` | Lat-long HDRI lookup done; **importance sampling stubbed** (uniform sphere placeholder) |

### `sampler`  `src/sampler/`

```zig
pub const Sampler = union(enum) {
    independent: Independent,
    halton:      Halton,
    // fn startPixel(px, py, sample_idx) void
    // fn next1d() f32
    // fn next2d() [2]f32
};
```

| File | Status |
|---|---|
| `independent.zig` | PCG32 RNG, per-pixel seeding — **done** |
| `halton.zig` | Base-2/3 radical inverse, per-pixel scramble — **done** |

### `film`  `src/film/`

| File | Status |
|---|---|
| `film.zig` | `Pixel` accumulation (sum + count), `toRgba8` with sRGB encoding — **done**; `writePng` and `writeExr` **stubbed** |
| `tonemap.zig` | `linear`, `reinhard`, `aces` (Narkowicz approximation) — **done** |

### `scene`  `src/scene/`

| File | Status |
|---|---|
| `camera.zig` | `PinholeCamera` (NDC ray gen) and `ThinLensCamera` (DoF, disk sampling) — **done** |
| `instance.zig` | `Instance` — wraps `Geometry` with object↔world transforms; ray transform in/out, world-space AABB from 8 corners — **done** |
| `scene.zig` | `Scene` struct; brute-force `intersect`/`intersectAny` routing (accel wired but not plumbed through yet) |
| `loader.zig` | `SceneLoader.cornellBox()` (hardcoded, working); `loadJson` and `ObjLoader.load` **stubbed** |

### `integrator`  `src/integrator/`

```zig
pub const Integrator = union(enum) {
    path_tracer: PathTracer,
    direct:      DirectLighting,
    debug:       DebugView,
    // fn li(ray, scene, sampler, alloc) Spectrum
    // fn liRecord(ray, scene, sampler, alloc, *PathRecord) Spectrum
};
```

| File | Status |
|---|---|
| `path_tracer.zig` | MIS with balance heuristic, Russian roulette, path recording for viz — **done** |
| `direct.zig` | Single-bounce direct lighting, all lights — **done** |
| `debug.zig` | `normals`, `shading_normals`, `albedo`, `depth`, `uv`, `path_length` modes — **done** |

**`PathRecord`** accumulates `PathSegment` values (origin, direction, lobe, throughput) for post-hoc path visualization.

### `viz`  `src/viz/`

| File | Status |
|---|---|
| `path_viz.zig` | Collects `PathRecord` instances; lobe→color mapping done; segment rasterization loop done; **world→raster projection stubbed** |

### `display`  `src/display/`

| File | Status |
|---|---|
| `sdl2.zig` | `Display` wrapping SDL2 window/renderer/streaming texture; `update(film, tonemap)` and `pollEvent` — **done** |

---

## Interactive Mode Key Bindings

| Key | Action |
|---|---|
| `R` | Reset accumulation buffer |
| Left-drag | Orbit camera (stub) |
| Scroll | Dolly zoom (stub) |
| Close window | Quit |

---

## Data Flow

```
Scene JSON / hardcoded
        │
        ▼
    SceneLoader
        │ builds
        ▼
      Scene ──────────────────────────────────────────────┐
    (camera, instances[], materials[], lights[], accel)   │
        │                                                  │
        ▼                                                  │
  main render loop                                         │
    for each pixel, spp:                                   │
      Sampler.startPixel()                                 │
      Camera.generateRay()  ──────────────────────────────┘
      Integrator.li(ray, &scene, &sampler)
        │  path_tracer:
        │    Scene.intersect(ray) → HitRecord
        │    material.emission()
        │    sampleDirectLighting() → shadow ray → Scene.intersectAny()
        │    material.sample() → next ray direction
        │    [PathRecord.append(segment)]
        │    Russian roulette
        │    recurse
        ▼
      Film.addSample(px, py, spectrum)
        │
        ▼
  Film.toRgba8(buf, tonemap)   ← Display.update() or writePng()
```

---

## Remaining Tasks

### P0 — Required for first render

- [ ] **`Mat4.inverse()`** (`src/math/mat4.zig`)
  Needed for transform instancing (Instance uses `world_to_object` to transform rays). Implement via cofactor expansion or the standard 4×4 analytical inverse.

- [ ] **`Scene.intersect` routes through `AccelStructure`** (`src/scene/scene.zig`)
  Currently brute-forces `self.instances` directly. Replace with `self.accel.intersect(ray)` and populate `accel` from the instance list during scene build.

- [ ] **`Film.writePng`** (`src/film/film.zig`)
  Add `zigimg` as a dependency (`zig fetch --save <url>`) or write a minimal PNG encoder. Wire into the build as a module import.

### P1 — Core functionality

- [ ] **`ObjLoader.load`** (`src/scene/loader.zig`)
  Parse `v`, `vn`, `vt`, `f` lines. Handle `mtllib`/`usemtl`. Build a `TriangleMesh` per `o`/`g` group, wrap in an `Instance` with identity transform.

- [ ] **`TriangleMesh.initFromArrays`** (`src/geometry/triangle_mesh.zig`)
  De-index OBJ face data into `Vertex`/`Triangle` arrays. Compute `bounds` from all vertex positions.

- [ ] **`SceneLoader.loadJson`** (`src/scene/loader.zig`)
  Use `std.json` to parse the schema documented in `loader.zig`. Dispatch to `ObjLoader` for mesh objects, construct analytic primitives directly.

- [ ] **`Bvh.build`** (`src/accel/bvh.zig`)
  SAH binned build (16–32 bins per axis). Recursive: compute centroid AABB, sweep bins for minimum cost, partition, recurse. Leaf threshold ~4 primitives.

- [ ] **`Bvh.intersect` / `intersectAny`** (`src/accel/bvh.zig`)
  Iterative traversal with a fixed-size stack (~64 entries). Order child visits by ray direction sign for early termination. `intersectAny` returns on first hit.

- [ ] **`AreaLight.sampleLi` + `pdfLi`** (`src/light/area_light.zig`)
  Call `geometry.sampleSurface(rng)` on the referenced instance, convert area PDF to solid-angle PDF: `pdf_sa = pdf_area * dist² / |cos θ_light|`.

- [ ] **`TriangleMesh.sampleSurface`** (`src/geometry/triangle_mesh.zig`)
  Precompute per-triangle area and a CDF. Sample a triangle by CDF, then uniformly sample a point via barycentric coordinates.

- [ ] **`Film.writeExr`** (`src/film/film.zig`)
  Minimal scanline EXR: HALF pixel type, 3 channels (R/G/B). The format header is ~200 lines of straightforward byte writing; no external library required.

### P2 — Quality & correctness

- [ ] **`Ggx` VNDF sampling** (`src/material/ggx.zig`)
  Replace the current NDF-based spherical sample with visible normal distribution function sampling (Heitz 2018, "Sampling the GGX Distribution of Visible Normals"). Reduces fireflies at low roughness.

- [ ] **`EnvLight` importance sampling** (`src/light/env_light.zig`)
  Build a 2D marginal/conditional CDF over the HDRI luminance at load time. Sample using inversion method. `pdfLi` returns the corresponding PDF.

- [ ] **`Plane` finite-extent bbox and surface sampling** (`src/geometry/analytic.zig`)
  Compute world-space AABB from the plane's tangent frame and half-extents. Uniform sampling over the rectangle.

- [ ] **`PathViz.projectToFilm`** (`src/viz/path_viz.zig`)
  Implement world→NDC→raster projection using the camera's view and projection matrices. Clip segments against the near plane.

- [ ] **Camera orbit in interactive mode** (`src/main.zig`)
  On `mouse_drag`, rotate the camera's `camera_to_world` matrix around the scene center using `Mat4.rotateY` / `Mat4.rotateX`. Reset film accumulation.

- [ ] **Dolly zoom** (`src/main.zig`)
  On scroll, translate the camera along its local -Z axis. Reset film accumulation.

### P3 — Extended features

- [ ] **CLI argument parser** (`src/main.zig`)
  Parse `--scene`, `--output`, `--width`, `--height`, `--spp`, `--integrator`, `--debug-mode`, `--tonemap`, `--viz-paths` using `std.process.argsAlloc`.

- [ ] **Multi-threading** (`src/main.zig`)
  Tile the image into e.g. 16×16 blocks. Dispatch tiles to a thread pool (`std.Thread.Pool`). Each tile gets its own `Sampler` state. Film writes are safe per-pixel.

- [ ] **`TriangleMesh` normal map support** (`src/geometry/triangle_mesh.zig`)
  Sample a tangent-space normal map texture at the UV coordinates, transform to world space using the per-vertex tangent frame (TBN matrix).

- [ ] **Two-level BVH (instancing)** (`src/accel/`)
  Add a `TwoLevelBvh` variant: a top-level BVH over instance bounding boxes, each leaf pointing to a per-geometry bottom-level BVH. Enables efficient instanced meshes.

- [ ] **Texture system** (`src/material/`)
  Add a `Texture = union(enum) { constant: Spectrum, image: ImageTexture }` type. Replace `Lambertian.albedo: Spectrum` with `albedo: Texture`. Require bilinear filtering.

- [ ] **Participating media (volumetrics)** (`src/integrator/`)
  Add a `HomogeneousMedium` type (sigma_a, sigma_s, phase function). Extend `PathTracer` with delta tracking or ratio tracking for unbiased transmittance estimation.

- [ ] **Denoiser integration** (`src/film/`)
  Write per-pixel AOV buffers (albedo, normal) alongside the beauty buffer. Optionally integrate Intel Open Image Denoise via C FFI for interactive preview.

---

## Build Reference

```bash
# Install Zig 0.13+ from https://ziglang.org/download/
# Install SDL2: apt install libsdl2-dev  |  brew install sdl2

zig build                         # compile
zig build run                     # run with defaults (Cornell box, 800×600, 64 spp)
zig build run -- --mode interactive  # SDL2 window (once CLI parser is done)
zig build test                    # white furnace + perf counter tests

# Add zigimg for PNG output:
zig fetch --save https://github.com/zigimg/zigimg/archive/<commit>.tar.gz
# then uncomment the zigimg block in build.zig.zon and build.zig
```

---

## Suggested Implementation Order

1. `Mat4.inverse` → enables transform instancing to work correctly
2. `Bvh.build` + `Bvh.intersect` → replace brute-force, required for non-trivial scenes
3. `ObjLoader` + `TriangleMesh.initFromArrays` → load real meshes
4. `Film.writePng` (via zigimg) → get output on disk
5. `SceneLoader.loadJson` → drive scenes from files rather than code
6. `AreaLight.sampleLi` + `TriangleMesh.sampleSurface` → proper Cornell box
7. `Ggx` VNDF sampling → correct glossy materials
8. CLI parser → usable as a standalone tool
9. Multi-threading → render speed
