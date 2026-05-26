const std = @import("std");
const math = @import("math");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Ray = math.Ray;

pub const PinholeCamera = struct {
    // Camera-to-world transform.
    camera_to_world: Mat4,
    // Precomputed from fov_y and aspect.
    tan_half_fov: f32,
    aspect: f32,

    pub fn init(camera_to_world: Mat4, fov_y_radians: f32, aspect: f32) PinholeCamera {
        return .{
            .camera_to_world = camera_to_world,
            .tan_half_fov = @tan(fov_y_radians * 0.5),
            .aspect = aspect,
        };
    }

    // px, py in [0,1) raster coordinates; rng unused (no DoF).
    pub fn generateRay(self: PinholeCamera, px: f32, py: f32, rng: [2]f32) Ray {
        _ = rng;
        // Map to NDC [-1,1]
        const x = (2.0 * px - 1.0) * self.aspect * self.tan_half_fov;
        const y = (1.0 - 2.0 * py) * self.tan_half_fov;
        const dir_cam = Vec3.init(x, y, -1.0);
        const origin = Mat4.transformPoint(self.camera_to_world, Vec3.zero());
        const dir_world = Vec3.normalize(Mat4.transformDirection(self.camera_to_world, dir_cam));
        return Ray.init(origin, dir_world);
    }
};

pub const ThinLensCamera = struct {
    pinhole: PinholeCamera,
    lens_radius: f32,
    focal_distance: f32,

    pub fn generateRay(self: ThinLensCamera, px: f32, py: f32, rng: [2]f32) Ray {
        const base = self.pinhole.generateRay(px, py, rng);
        if (self.lens_radius == 0) return base;

        // Sample a disk on the lens.
        const angle = rng[0] * 2.0 * std.math.pi;
        const r = @sqrt(rng[1]) * self.lens_radius;
        const lens_offset = Vec3.init(@cos(angle) * r, @sin(angle) * r, 0);

        // Find the focal point along the base ray.
        const ft = self.focal_distance / (-base.direction.z);
        const focus_point = base.at(ft);

        const origin = Vec3.add(base.origin, Mat4.transformDirection(self.pinhole.camera_to_world, lens_offset));
        const direction = Vec3.normalize(Vec3.sub(focus_point, origin));
        return Ray.init(origin, direction);
    }
};

pub const Camera = union(enum) {
    pinhole: PinholeCamera,
    thin_lens: ThinLensCamera,

    pub fn generateRay(self: Camera, px: f32, py: f32, rng: [2]f32) Ray {
        return switch (self) {
            inline else => |c| c.generateRay(px, py, rng),
        };
    }
};
