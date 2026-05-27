// Root test file. Each sub-module's tests are compiled in via these imports.
const std = @import("std");

// Import test modules
comptime {
    _ = @import("white_furnace.zig");
    _ = @import("perf");
}

// Import module-local tests
const math = @import("math");
comptime {
    _ = math.Vec3; // triggers vec3 tests
}
