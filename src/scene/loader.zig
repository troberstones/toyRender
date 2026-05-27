const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Spectrum = math.Spectrum;
const geometry = @import("geometry");
const TriangleMesh = geometry.TriangleMesh;
const Vertex = geometry.TriangleMesh.Vertex; // not yet exported from root — TODO
const Geometry = geometry.Geometry;
const material_mod = @import("material");
const Material = material_mod.Material;
const Lambertian = material_mod.Lambertian;
const light_mod = @import("light");
const Light = light_mod.Light;
const Scene = @import("scene.zig").Scene;
const Instance = @import("instance.zig").Instance;
const Camera = @import("camera.zig").Camera;
const PinholeCamera = @import("camera.zig").PinholeCamera;
const accel_mod = @import("accel");

// --- OBJ / MTL loader ---

pub const ObjLoader = struct {
    pub fn load(
        alloc: std.mem.Allocator,
        path: []const u8,
        material_offset: u32,
    ) ![]Instance {
        _ = alloc;
        _ = path;
        _ = material_offset;
        // TODO:
        //   1. Parse vertex positions (v), normals (vn), UVs (vt), faces (f)
        //   2. Handle mtllib / usemtl directives
        //   3. Build TriangleMesh per group, wrap in Instance with identity transform
        @panic("ObjLoader.load not yet implemented");
    }
};

// --- JSON scene loader ---
//
// Expected schema (see scenes/cornell_box.json for a full example):
// {
//   "camera": { "type": "pinhole", "fov_y": 40, "from": [...], "to": [...], "up": [...] },
//   "background": [r, g, b],
//   "materials": [ { "type": "lambertian", "albedo": [r,g,b] }, ... ],
//   "objects": [
//     { "type": "obj", "path": "mesh.obj", "material": 0, "transform": { ... } },
//     { "type": "sphere", "center": [...], "radius": 1.0, "material": 0 }
//   ],
//   "lights": [ { "type": "point", "position": [...], "intensity": [r,g,b] } ]
// }

pub const SceneLoader = struct {
    pub fn loadJson(alloc: std.mem.Allocator, path: []const u8) !Scene {
        _ = alloc;
        _ = path;
        // TODO: parse with std.json, dispatch to sub-loaders
        @panic("SceneLoader.loadJson not yet implemented");
    }

    // Build a hardcoded Cornell box scene for testing without a JSON file.
    pub fn cornellBox(alloc: std.mem.Allocator) !Scene {
        var materials = try alloc.alloc(Material, 5);
        materials[0] = .{ .lambertian = .{ .albedo = Spectrum.init(0.73, 0.73, 0.73) } }; // white
        materials[1] = .{ .lambertian = .{ .albedo = Spectrum.init(0.65, 0.05, 0.05) } }; // red
        materials[2] = .{ .lambertian = .{ .albedo = Spectrum.init(0.12, 0.45, 0.15) } }; // green
        materials[3] = .{ .lambertian = .{ .albedo = Spectrum.init(1.0, 1.0, 1.0) } };    // light (white emissive)
        materials[4] = .{ .specular = .{ .reflectance = Spectrum.one() } };                // mirror

        const instances = try alloc.alloc(Instance, 6);
        const id = Mat4.identity();

        // Floor
        instances[0] = Instance.init(.{ .sphere = .{ .center = Vec3.init(0, -100.5, -1), .radius = 100, .material_index = 0 } }, id, id, 0);
        // Red wall (left)
        instances[1] = Instance.init(.{ .sphere = .{ .center = Vec3.init(-101.5, 0, -1), .radius = 100, .material_index = 1 } }, id, id, 1);
        // Green wall (right)
        instances[2] = Instance.init(.{ .sphere = .{ .center = Vec3.init(101.5, 0, -1), .radius = 100, .material_index = 2 } }, id, id, 2);
        // White small sphere
        instances[3] = Instance.init(.{ .sphere = .{ .center = Vec3.init(-0.5, 0, -1.5), .radius = 0.5, .material_index = 0 } }, id, id, 0);
        // Mirror sphere
        instances[4] = Instance.init(.{ .sphere = .{ .center = Vec3.init(0.5, 0, -1), .radius = 0.5, .material_index = 4 } }, id, id, 4);
        // Ceiling light sphere
        instances[5] = Instance.init(.{ .sphere = .{ .center = Vec3.init(0, 101.3, -1), .radius = 100, .material_index = 3 } }, id, id, 3);

        const lights = try alloc.alloc(Light, 1);
        lights[0] = .{ .point = .{ .position = Vec3.init(0, 1.2, -1), .intensity = Spectrum.splat(3.0) } };

        const cam = Camera{ .pinhole = PinholeCamera.init(
            Mat4.translate(0, 0.5, 2),
            std.math.degreesToRadians(40.0),
            1.0,
        ) };

        return Scene{
            .camera = cam,
            .instances = instances,
            .materials = materials,
            .lights = lights,
            .accel = .{ .brute_force = .{ .instances = &.{} } },
            .background = Spectrum.init(0.01, 0.01, 0.01),
            .alloc = alloc,
        };
    }
};
