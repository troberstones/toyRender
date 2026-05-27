// Lightweight reference passed into the accel structure at build time.
// Avoids a circular dependency between accel <-> scene.
const math = @import("math");
const Ray = math.Ray;
const AABB = math.AABB;
const geometry = @import("geometry");
const HitRecord = geometry.HitRecord;

pub const InstanceRef = struct {
    bbox: AABB,
    // Opaque pointer back to the owning Instance; caller casts it.
    ptr: *const anyopaque,
    intersectFn:  *const fn (ptr: *const anyopaque, ray: Ray, t_min: f32, t_max: f32, out: *HitRecord) bool,
    intersectTFn: *const fn (ptr: *const anyopaque, ray: Ray, t_min: f32, t_max: f32) ?f32,

    pub fn intersect(self: InstanceRef, ray: Ray, t_min: f32, t_max: f32, out: *HitRecord) bool {
        return self.intersectFn(self.ptr, ray, t_min, t_max, out);
    }

    // Fast t-only test for shadow rays.
    pub fn intersectT(self: InstanceRef, ray: Ray, t_min: f32, t_max: f32) ?f32 {
        return self.intersectTFn(self.ptr, ray, t_min, t_max);
    }
};
