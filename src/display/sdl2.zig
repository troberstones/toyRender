// SDL2 interactive display.
// Uses extern declarations instead of @cImport to avoid Zig 0.16's
// bundled arm_neon.h incompatibility on Apple Silicon.
const std = @import("std");
const math = @import("math");
const film_mod = @import("film");
const Film = film_mod.Film;
const Tonemap = film_mod.Tonemap;

// --- Opaque SDL2 types ---
const SDL_Window   = opaque {};
const SDL_Renderer = opaque {};
const SDL_Texture  = opaque {};

// SDL_Event is always 56 bytes (SDL_MAXEVENTSIZE). We store it as an aligned
// array and use the accessor functions in sdl2_bind.c to read fields.
const SDL_Event = extern struct { data: [14]u32 };

// --- SDL2 function declarations ---
extern fn SDL_Init(flags: u32) c_int;
extern fn SDL_Quit() void;
extern fn SDL_GetError() [*:0]const u8;

extern fn SDL_CreateWindow(title: [*:0]const u8, x: c_int, y: c_int, w: c_int, h: c_int, flags: u32) ?*SDL_Window;
extern fn SDL_DestroyWindow(w: *SDL_Window) void;

extern fn SDL_CreateRenderer(w: *SDL_Window, index: c_int, flags: u32) ?*SDL_Renderer;
extern fn SDL_DestroyRenderer(r: *SDL_Renderer) void;

extern fn SDL_CreateTexture(r: *SDL_Renderer, format: u32, access: c_int, w: c_int, h: c_int) ?*SDL_Texture;
extern fn SDL_DestroyTexture(t: *SDL_Texture) void;

extern fn SDL_UpdateTexture(t: *SDL_Texture, rect: ?*anyopaque, pixels: *const anyopaque, pitch: c_int) c_int;
extern fn SDL_RenderClear(r: *SDL_Renderer) c_int;
extern fn SDL_RenderCopy(r: *SDL_Renderer, t: *SDL_Texture, src: ?*anyopaque, dst: ?*anyopaque) c_int;
extern fn SDL_RenderPresent(r: *SDL_Renderer) void;

extern fn SDL_PollEvent(e: *SDL_Event) c_int;

// --- Event field accessors (from sdl2_bind.c) ---
extern fn sdl2_event_type(e: *const SDL_Event) u32;
extern fn sdl2_key_sym(e: *const SDL_Event) i32;
extern fn sdl2_motion_state(e: *const SDL_Event) u32;
extern fn sdl2_motion_xrel(e: *const SDL_Event) i32;
extern fn sdl2_motion_yrel(e: *const SDL_Event) i32;
extern fn sdl2_wheel_y(e: *const SDL_Event) i32;
extern fn sdl2_PIXELFORMAT_RGBA8888() u32;

// --- SDL2 constants ---
const SDL_INIT_VIDEO:           u32 = 0x00000020;
const SDL_WINDOWPOS_CENTERED: c_int = 0x2FFF0000;
const SDL_WINDOW_SHOWN:         u32 = 0x00000004;
const SDL_WINDOW_RESIZABLE:     u32 = 0x00000020;
const SDL_RENDERER_ACCELERATED: u32 = 0x00000002;
const SDL_TEXTUREACCESS_STREAMING: c_int = 1;
const SDL_QUIT:        u32 = 0x100;
const SDL_KEYDOWN:     u32 = 0x300;
const SDL_MOUSEMOTION: u32 = 0x400;
const SDL_MOUSEWHEEL:  u32 = 0x403;
const SDL_BUTTON_LMASK: u32 = 1; // SDL_BUTTON(SDL_BUTTON_LEFT) = 1 << 0

// --- Public API ---
pub const DisplayEvent = union(enum) {
    quit,
    key_press: u32,
    mouse_drag: [2]f32,
    mouse_scroll: f32,
};

pub const Display = struct {
    window:    *SDL_Window,
    renderer:  *SDL_Renderer,
    texture:   *SDL_Texture,
    width:     u32,
    height:    u32,
    pixel_buf: []u8,
    alloc:     std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, title: [:0]const u8, width: u32, height: u32) !Display {
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            std.log.err("SDL_Init failed: {s}", .{SDL_GetError()});
            return error.SdlInitFailed;
        }
        const win = SDL_CreateWindow(
            title.ptr,
            SDL_WINDOWPOS_CENTERED,
            SDL_WINDOWPOS_CENTERED,
            @intCast(width),
            @intCast(height),
            SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE,
        ) orelse return error.SdlWindowFailed;

        const ren = SDL_CreateRenderer(win, -1, SDL_RENDERER_ACCELERATED)
            orelse return error.SdlRendererFailed;

        const tex = SDL_CreateTexture(
            ren,
            sdl2_PIXELFORMAT_RGBA8888(),
            SDL_TEXTUREACCESS_STREAMING,
            @intCast(width),
            @intCast(height),
        ) orelse return error.SdlTextureFailed;

        const pixel_buf = try alloc.alloc(u8, width * height * 4);
        return .{
            .window    = win,
            .renderer  = ren,
            .texture   = tex,
            .width     = width,
            .height    = height,
            .pixel_buf = pixel_buf,
            .alloc     = alloc,
        };
    }

    pub fn deinit(self: *Display) void {
        self.alloc.free(self.pixel_buf);
        SDL_DestroyTexture(self.texture);
        SDL_DestroyRenderer(self.renderer);
        SDL_DestroyWindow(self.window);
        SDL_Quit();
    }

    pub fn update(self: *Display, film: *const Film, tonemap: Tonemap) void {
        film.toRgba8(self.pixel_buf, tonemap);
        _ = SDL_UpdateTexture(self.texture, null, self.pixel_buf.ptr, @intCast(self.width * 4));
        _ = SDL_RenderClear(self.renderer);
        _ = SDL_RenderCopy(self.renderer, self.texture, null, null);
        SDL_RenderPresent(self.renderer);
    }

    pub fn pollEvent(self: *Display) ?DisplayEvent {
        var ev: SDL_Event = undefined;
        while (SDL_PollEvent(&ev) != 0) {
            switch (sdl2_event_type(&ev)) {
                SDL_QUIT        => return .quit,
                SDL_KEYDOWN     => return .{ .key_press = @bitCast(sdl2_key_sym(&ev)) },
                SDL_MOUSEMOTION => {
                    if (sdl2_motion_state(&ev) & SDL_BUTTON_LMASK != 0) {
                        return .{ .mouse_drag = .{
                            @as(f32, @floatFromInt(sdl2_motion_xrel(&ev))) / @as(f32, @floatFromInt(self.width)),
                            @as(f32, @floatFromInt(sdl2_motion_yrel(&ev))) / @as(f32, @floatFromInt(self.height)),
                        }};
                    }
                },
                SDL_MOUSEWHEEL  => return .{ .mouse_scroll = @floatFromInt(sdl2_wheel_y(&ev)) },
                else            => {},
            }
        }
        return null;
    }
};
