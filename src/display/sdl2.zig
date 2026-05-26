// SDL2 interactive display. Linked via exe.linkSystemLibrary("SDL2").
const std = @import("std");
const c = @cImport({
    @cInclude("SDL2/SDL.h");
});
const math = @import("math");
const film_mod = @import("film");
const Film = film_mod.Film;
const Tonemap = film_mod.Tonemap;

pub const DisplayEvent = union(enum) {
    quit,
    key_press: u32,     // SDL keycode
    mouse_drag: [2]f32, // delta in normalized coords
    mouse_scroll: f32,
};

pub const Display = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    texture: *c.SDL_Texture,
    width: u32,
    height: u32,
    pixel_buf: []u8,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, title: [:0]const u8, width: u32, height: u32) !Display {
        if (c.SDL_Init(c.SDL_INIT_VIDEO) != 0) {
            std.log.err("SDL_Init failed: {s}", .{c.SDL_GetError()});
            return error.SdlInitFailed;
        }
        const win = c.SDL_CreateWindow(
            title.ptr,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            @intCast(width),
            @intCast(height),
            c.SDL_WINDOW_SHOWN | c.SDL_WINDOW_RESIZABLE,
        ) orelse return error.SdlWindowFailed;

        const ren = c.SDL_CreateRenderer(win, -1, c.SDL_RENDERER_ACCELERATED) orelse return error.SdlRendererFailed;

        const tex = c.SDL_CreateTexture(
            ren,
            c.SDL_PIXELFORMAT_RGBA8888,
            c.SDL_TEXTUREACCESS_STREAMING,
            @intCast(width),
            @intCast(height),
        ) orelse return error.SdlTextureFailed;

        const pixel_buf = try alloc.alloc(u8, width * height * 4);
        return .{
            .window = win,
            .renderer = ren,
            .texture = tex,
            .width = width,
            .height = height,
            .pixel_buf = pixel_buf,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Display) void {
        self.alloc.free(self.pixel_buf);
        c.SDL_DestroyTexture(self.texture);
        c.SDL_DestroyRenderer(self.renderer);
        c.SDL_DestroyWindow(self.window);
        c.SDL_Quit();
    }

    pub fn update(self: *Display, film: *const Film, tonemap: Tonemap) void {
        film.toRgba8(self.pixel_buf, tonemap);
        _ = c.SDL_UpdateTexture(self.texture, null, self.pixel_buf.ptr, @intCast(self.width * 4));
        _ = c.SDL_RenderClear(self.renderer);
        _ = c.SDL_RenderCopy(self.renderer, self.texture, null, null);
        c.SDL_RenderPresent(self.renderer);
    }

    pub fn pollEvent(self: *Display) ?DisplayEvent {
        var ev: c.SDL_Event = undefined;
        while (c.SDL_PollEvent(&ev) != 0) {
            switch (ev.type) {
                c.SDL_QUIT => return .quit,
                c.SDL_KEYDOWN => return .{ .key_press = @intCast(ev.key.keysym.sym) },
                c.SDL_MOUSEMOTION => {
                    if (ev.motion.state & c.SDL_BUTTON_LMASK != 0) {
                        return .{ .mouse_drag = .{
                            @as(f32, @floatFromInt(ev.motion.xrel)) / @as(f32, @floatFromInt(self.width)),
                            @as(f32, @floatFromInt(ev.motion.yrel)) / @as(f32, @floatFromInt(self.height)),
                        } };
                    }
                },
                c.SDL_MOUSEWHEEL => return .{ .mouse_scroll = @floatFromInt(ev.wheel.y) },
                else => {},
            }
        }
        return null;
    }
};
