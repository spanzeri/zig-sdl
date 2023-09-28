const std = @import("std");
const c = @cImport({
    @cInclude("SDL3/SDL.h");
});

test "simple" {
    const err = c.SDL_Init(c.SDL_INIT_VIDEO);
    if (err != 0) {
        std.log.err("SDL initialisation failed with error: {s}", .{ c.SDL_GetError() });
        return error.sdl_init_failed;
    }
    defer c.SDL_Quit();

    const window = c.SDL_CreateWindow(
        "hello SDL", 800, 600, 0);
    defer c.SDL_DestroyWindow(window);

    c.SDL_Delay(2000);
}
