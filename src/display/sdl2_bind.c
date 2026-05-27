// Thin C shim so Zig can call SDL2 without @cImport.
// Compiled by the system toolchain, which knows the ARM builtins that
// Zig 0.16's bundled translate-c does not support.
#include <SDL2/SDL.h>
#include <stdint.h>

// SDL_Event is padded to 56 bytes in SDL2.
// Expose field accessors so Zig never needs the full struct layout.
uint32_t sdl2_event_type(const void *e)   { return ((const SDL_Event *)e)->type; }
int32_t  sdl2_key_sym(const void *e)      { return (int32_t)((const SDL_Event *)e)->key.keysym.sym; }
uint32_t sdl2_motion_state(const void *e) { return ((const SDL_Event *)e)->motion.state; }
int32_t  sdl2_motion_xrel(const void *e)  { return ((const SDL_Event *)e)->motion.xrel; }
int32_t  sdl2_motion_yrel(const void *e)  { return ((const SDL_Event *)e)->motion.yrel; }
int32_t  sdl2_wheel_y(const void *e)      { return ((const SDL_Event *)e)->wheel.y; }

// SDL_PIXELFORMAT_RGBA8888 is a computed enum — expose it as a function.
uint32_t sdl2_PIXELFORMAT_RGBA8888(void)  { return SDL_PIXELFORMAT_RGBA8888; }

// Sanity-check the event size assumption made on the Zig side.
_Static_assert(sizeof(SDL_Event) == 56, "SDL_Event size changed — update Zig binding");
