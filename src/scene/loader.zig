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

// --- OBJ loader ---

pub const ObjLoader = struct {
    pub fn load(
        alloc: std.mem.Allocator,
        path: []const u8,
        material_index: u32,
    ) ![]Instance {
        const io = std.Options.debug_io;
        const content = try std.Io.Dir.cwd().readFileAlloc(
            io, path, alloc, std.Io.Limit.limited(64 * 1024 * 1024),
        );
        defer alloc.free(content);

        var positions: std.ArrayList(Vec3) = .empty;
        defer positions.deinit(alloc);
        var normals: std.ArrayList(Vec3) = .empty;
        defer normals.deinit(alloc);
        var uvs: std.ArrayList([2]f32) = .empty;
        defer uvs.deinit(alloc);
        var idx_buf: std.ArrayList(u32) = .empty;
        defer idx_buf.deinit(alloc);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |raw| {
            const line = std.mem.trim(u8, raw, " \t\r");
            if (line.len == 0 or line[0] == '#') continue;

            if (std.mem.startsWith(u8, line, "vn ")) {
                if (parseVec3(line[3..])) |n| try normals.append(alloc, n);
            } else if (std.mem.startsWith(u8, line, "vt ")) {
                if (parseVec2(line[3..])) |uv| try uvs.append(alloc, uv);
            } else if (std.mem.startsWith(u8, line, "v ")) {
                if (parseVec3(line[2..])) |p| try positions.append(alloc, p);
            } else if (std.mem.startsWith(u8, line, "f ")) {
                try parseFace(alloc, line[2..], &idx_buf);
            }
            // mtllib / usemtl / o / g / s: ignored for now
        }

        const mesh = try TriangleMesh.initFromArrays(
            alloc,
            positions.items,
            normals.items,
            uvs.items,
            idx_buf.items,
            material_index,
        );

        const instances = try alloc.alloc(Instance, 1);
        const id = Mat4.identity();
        instances[0] = Instance.init(.{ .triangle_mesh = mesh }, id, id, material_index);
        return instances;
    }

    fn parseVec3(s: []const u8) ?Vec3 {
        var it = std.mem.tokenizeScalar(u8, s, ' ');
        const x = std.fmt.parseFloat(f32, it.next() orelse return null) catch return null;
        const y = std.fmt.parseFloat(f32, it.next() orelse return null) catch return null;
        const z = std.fmt.parseFloat(f32, it.next() orelse return null) catch return null;
        return Vec3.init(x, y, z);
    }

    fn parseVec2(s: []const u8) ?[2]f32 {
        var it = std.mem.tokenizeScalar(u8, s, ' ');
        const u = std.fmt.parseFloat(f32, it.next() orelse return null) catch return null;
        const v = std.fmt.parseFloat(f32, it.next() orelse return null) catch return null;
        return .{ u, v };
    }

    // Appends (pos, norm, uv) index triples for each triangle of the face (fan triangulation).
    fn parseFace(alloc: std.mem.Allocator, s: []const u8, buf: *std.ArrayList(u32)) !void {
        var spec: [8][3]u32 = undefined;
        var n: u32 = 0;

        var it = std.mem.tokenizeScalar(u8, s, ' ');
        while (it.next()) |tok| {
            if (n >= 8) break;
            spec[n] = parseFaceVert(tok);
            n += 1;
        }
        if (n < 3) return;

        // Fan from vertex 0
        for (1..@as(usize, n) - 1) |i| {
            for ([_][3]u32{ spec[0], spec[i], spec[i + 1] }) |v| {
                try buf.append(alloc, v[0]); // position index
                try buf.append(alloc, v[1]); // normal index
                try buf.append(alloc, v[2]); // uv index
            }
        }
    }

    // Parses "i", "i/j", "i/j/k", or "i//k".  Returns 0-based indices.
    fn parseFaceVert(tok: []const u8) [3]u32 {
        var parts = std.mem.splitScalar(u8, tok, '/');
        const pos_s = parts.next() orelse "1";
        const uv_s  = parts.next() orelse "";
        const nrm_s = parts.next() orelse "";

        // OBJ uses 1-based positive indices; negative indices (relative) not handled.
        const pi  = (std.fmt.parseInt(u32, pos_s, 10) catch 1) -| 1;
        const uvi = if (uv_s.len  > 0) (std.fmt.parseInt(u32, uv_s,  10) catch 1) -| 1 else 0;
        const ni  = if (nrm_s.len > 0) (std.fmt.parseInt(u32, nrm_s, 10) catch 1) -| 1 else 0;

        return .{ pi, ni, uvi };
    }
};

// --- JSON scene loader ---
//
// Expected schema (see scenes/cornell_box.json for a full example):
// {
//   "camera": { "type": "pinhole", "fov_y": 40, "from": [...], "to": [...], "up": [...] },
//   "background": [r, g, b],
//   "materials": [ { "id": "name", "type": "lambertian", "albedo": [r,g,b] }, ... ],
//   "objects": [
//     { "type": "obj", "path": "mesh.obj", "material": "name", "transform": { ... } },
//     { "type": "sphere", "center": [...], "radius": 1.0, "material": "name" }
//   ],
//   "lights": [ { "type": "area", "instance": "comment_name", "emission": [r,g,b] } ]
// }

pub const SceneLoader = struct {
    pub fn loadJson(alloc: std.mem.Allocator, path: []const u8) !Scene {
        const io = std.Options.debug_io;
        const content = try std.Io.Dir.cwd().readFileAlloc(
            io, path, alloc, std.Io.Limit.limited(8 * 1024 * 1024),
        );
        defer alloc.free(content);

        const parsed = try std.json.parseFromSlice(std.json.Value, alloc, content, .{});
        defer parsed.deinit();
        const root = parsed.value.object;

        // Directory that contains the scene file; used to resolve relative OBJ paths.
        const scene_dir = std.fs.path.dirname(path) orelse ".";

        // ---------------------------------------------------------------- materials
        const mat_arr = if (root.get("materials")) |m| m.array.items else &[_]std.json.Value{};
        const materials = try alloc.alloc(Material, mat_arr.len);
        errdefer alloc.free(materials);

        var mat_ids = std.StringHashMap(u32).init(alloc);
        defer mat_ids.deinit();

        for (mat_arr, 0..) |mv, i| {
            const mo = mv.object;
            if (mo.get("id")) |id_val| try mat_ids.put(id_val.string, @intCast(i));

            const typ = mo.get("type").?.string;
            if (std.mem.eql(u8, typ, "lambertian")) {
                const albedo   = spectrumFromJson(mo.get("albedo") orelse return error.MissingField);
                const emissive = if (mo.get("emission")) |e| spectrumFromJson(e) else Spectrum.zero();
                materials[i] = .{ .lambertian = .{ .albedo = albedo, .emissive = emissive } };
            } else if (std.mem.eql(u8, typ, "specular")) {
                const refl = spectrumFromJson(mo.get("reflectance") orelse return error.MissingField);
                materials[i] = .{ .specular = .{ .reflectance = refl } };
            } else if (std.mem.eql(u8, typ, "dielectric")) {
                const ior  = asFloat(mo.get("ior") orelse return error.MissingField);
                const tint = if (mo.get("tint")) |t| spectrumFromJson(t) else Spectrum.one();
                materials[i] = .{ .dielectric = .{ .ior = @floatCast(ior), .tint = tint } };
            } else {
                return error.UnknownMaterialType;
            }
        }

        // ---------------------------------------------------------------- objects
        var inst_list: std.ArrayList(Instance) = .empty;
        errdefer inst_list.deinit(alloc);

        // Map from "comment" string → first instance index (for area light lookup).
        var inst_names = std.StringHashMap(u32).init(alloc);
        defer inst_names.deinit();

        const obj_arr = if (root.get("objects")) |o| o.array.items else &[_]std.json.Value{};
        for (obj_arr) |ov| {
            const obj = ov.object;
            const typ = obj.get("type").?.string;

            const mat_id  = obj.get("material").?.string;
            const mat_idx = mat_ids.get(mat_id) orelse return error.UnknownMaterial;

            const xform     = if (obj.get("transform")) |t| parseTransform(t) else Mat4.identity();
            const xform_inv = Mat4.inverse(xform);

            const comment = if (obj.get("comment")) |c| c.string else "";
            const base_inst_idx: u32 = @intCast(inst_list.items.len);

            if (std.mem.eql(u8, typ, "sphere")) {
                const center = vec3FromJson(obj.get("center") orelse return error.MissingField);
                const radius: f32 = @floatCast(asFloat(obj.get("radius") orelse return error.MissingField));
                const geo = Geometry{ .sphere = .{ .center = center, .radius = radius, .material_index = mat_idx } };
                try inst_list.append(alloc, Instance.init(geo, xform, xform_inv, mat_idx));
            } else if (std.mem.eql(u8, typ, "obj")) {
                const rel = obj.get("path").?.string;
                const abs = try std.fs.path.join(alloc, &.{ scene_dir, rel });
                defer alloc.free(abs);

                const loaded = try ObjLoader.load(alloc, abs, mat_idx);
                defer alloc.free(loaded);

                for (loaded) |li| {
                    const final = Mat4.mul(xform, li.object_to_world);
                    const final_inv = Mat4.inverse(final);
                    try inst_list.append(alloc, Instance.init(li.geometry, final, final_inv, mat_idx));
                }
            } else {
                return error.UnknownObjectType;
            }

            if (comment.len > 0) try inst_names.put(comment, base_inst_idx);
        }

        const instances = try inst_list.toOwnedSlice(alloc);
        errdefer alloc.free(instances);

        // ---------------------------------------------------------------- lights
        var light_list: std.ArrayList(Light) = .empty;
        errdefer light_list.deinit(alloc);

        const light_arr = if (root.get("lights")) |l| l.array.items else &[_]std.json.Value{};
        for (light_arr) |lv| {
            const lo  = lv.object;
            const typ = lo.get("type").?.string;
            if (std.mem.eql(u8, typ, "point")) {
                const pos   = vec3FromJson(lo.get("position") orelse return error.MissingField);
                const intens = spectrumFromJson(lo.get("intensity") orelse return error.MissingField);
                try light_list.append(alloc, .{ .point = .{ .position = pos, .intensity = intens } });
            } else if (std.mem.eql(u8, typ, "area")) {
                const name   = lo.get("instance").?.string;
                const iidx   = inst_names.get(name) orelse return error.UnknownLightInstance;
                const emis   = spectrumFromJson(lo.get("emission") orelse return error.MissingField);
                try light_list.append(alloc, .{ .area = .{
                    .instance_index = iidx,
                    .emission       = emis,
                    .surface_area   = 1.0,
                }});
            } else {
                return error.UnknownLightType;
            }
        }

        const lights = try light_list.toOwnedSlice(alloc);
        errdefer alloc.free(lights);

        // ---------------------------------------------------------------- camera
        const cam_obj = (root.get("camera") orelse return error.MissingField).object;
        const cam_type = cam_obj.get("type").?.string;
        const camera = if (std.mem.eql(u8, cam_type, "pinhole")) blk: {
            const fov_deg: f32 = @floatCast(asFloat(cam_obj.get("fov_y") orelse return error.MissingField));
            const from = vec3FromJson(cam_obj.get("from") orelse return error.MissingField);
            const to   = vec3FromJson(cam_obj.get("to")   orelse return error.MissingField);
            const up   = vec3FromJson(cam_obj.get("up")   orelse return error.MissingField);
            const ctw  = Mat4.lookAt(from, to, up);
            break :blk Camera{ .pinhole = PinholeCamera.init(ctw, std.math.degreesToRadians(fov_deg), 1.0) };
        } else return error.UnknownCameraType;

        const background = if (root.get("background")) |bg| spectrumFromJson(bg) else Spectrum.zero();

        // ---------------------------------------------------------------- accel
        const refs = try alloc.alloc(accel_mod.InstanceRef, instances.len);
        defer alloc.free(refs);
        for (instances, refs) |*inst, *ref| ref.* = inst.toRef();
        var bvh = try accel_mod.Bvh.build(alloc, refs);
        const qbvh = try accel_mod.Qbvh.fromBvh(alloc, bvh);
        bvh.deinit(alloc);

        return Scene{
            .camera     = camera,
            .instances  = instances,
            .materials  = materials,
            .lights     = lights,
            .accel      = .{ .qbvh = qbvh },
            .background = background,
            .alloc      = alloc,
        };
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

        // Build InstanceRef slice (temporary — Bvh.build dupes it internally).
        const refs = try alloc.alloc(accel_mod.InstanceRef, instances.len);
        defer alloc.free(refs);
        for (instances, refs) |*inst, *ref| {
            ref.* = inst.toRef();
        }
        var bvh = try accel_mod.Bvh.build(alloc, refs);
        const qbvh = try accel_mod.Qbvh.fromBvh(alloc, bvh);
        bvh.deinit(alloc);

        return Scene{
            .camera = cam,
            .instances = instances,
            .materials = materials,
            .lights = lights,
            .accel = .{ .qbvh = qbvh },
            .background = Spectrum.init(0.01, 0.01, 0.01),
            .alloc = alloc,
        };
    }
};

// --- Helpers ---

fn asFloat(val: std.json.Value) f64 {
    return switch (val) {
        .float   => |f| f,
        .integer => |i| @floatFromInt(i),
        else     => 0,
    };
}

fn spectrumFromJson(val: std.json.Value) Spectrum {
    const a = val.array.items;
    return Spectrum.init(
        @floatCast(asFloat(a[0])),
        @floatCast(asFloat(a[1])),
        @floatCast(asFloat(a[2])),
    );
}

fn vec3FromJson(val: std.json.Value) Vec3 {
    const a = val.array.items;
    return Vec3.init(
        @floatCast(asFloat(a[0])),
        @floatCast(asFloat(a[1])),
        @floatCast(asFloat(a[2])),
    );
}

// Parses a transform object.  Multiple keys compose as T*R*S (TRS order).
fn parseTransform(val: std.json.Value) Mat4 {
    const obj = val.object;
    var m = Mat4.identity();
    if (obj.get("scale")) |sv| {
        const v = vec3FromJson(sv);
        m = Mat4.mul(Mat4.scale(v.x, v.y, v.z), m);
    }
    if (obj.get("rotate_x")) |rv| m = Mat4.mul(Mat4.rotateX(std.math.degreesToRadians(@as(f32, @floatCast(asFloat(rv))))), m);
    if (obj.get("rotate_y")) |rv| m = Mat4.mul(Mat4.rotateY(std.math.degreesToRadians(@as(f32, @floatCast(asFloat(rv))))), m);
    if (obj.get("rotate_z")) |rv| m = Mat4.mul(Mat4.rotateZ(std.math.degreesToRadians(@as(f32, @floatCast(asFloat(rv))))), m);
    if (obj.get("translate")) |tv| {
        const v = vec3FromJson(tv);
        m = Mat4.mul(Mat4.translate(v.x, v.y, v.z), m);
    }
    return m;
}
