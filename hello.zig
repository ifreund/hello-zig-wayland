const std = @import("std");
const os = std.os;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const Context = struct {
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    wm_base: ?*xdg.WmBase,
};

pub fn main() anyerror!void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var context = Context{
        .shm = null,
        .compositor = null,
        .wm_base = null,
    };

    try registry.setListener(*Context, registryListener, &context);
    _ = try display.roundtrip();

    const shm = context.shm orelse return error.NoWlShm;
    const compositor = context.compositor orelse return error.NoWlCompositor;
    const wm_base = context.wm_base orelse return error.NoXdgWmBase;

    const buffer = blk: {
        const width = 128;
        const height = 128;
        const stride = width * 4;
        const size = stride * height;

        const fd = try os.memfd_create("hello-zig-wayland", 0);
        try os.ftruncate(fd, size);
        const data = try os.mmap(null, size, os.PROT_READ | os.PROT_WRITE, os.MAP_SHARED, fd, 0);
        std.mem.copy(u8, data, @embedFile("cat.bgra"));

        const pool = try shm.createPool(fd, size);
        defer pool.destroy();

        break :blk try pool.createBuffer(0, width, height, stride, @enumToInt(wl.Shm.Format.argb8888));
    };
    defer buffer.destroy();

    const surface = try compositor.createSurface();
    defer surface.destroy();
    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();
    const xdg_toplevel = try xdg_surface.getToplevel();
    defer xdg_toplevel.destroy();

    var running = true;

    try xdg_surface.setListener(*wl.Surface, xdgSurfaceListener, surface);
    try xdg_toplevel.setListener(*bool, xdgToplevelListener, &running);

    surface.commit();
    _ = try display.roundtrip();

    surface.attach(buffer, 0, 0);
    surface.commit();

    while (running) _ = try display.dispatch();
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, wl.Compositor.interface().name) == 0) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Shm.interface().name) == 0) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.cstr.cmp(global.interface, xdg.WmBase.interface().name) == 0) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, surface: *wl.Surface) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            surface.commit();
        },
    }
}

fn xdgToplevelListener(xdg_toplevel: *xdg.Toplevel, event: xdg.Toplevel.Event, running: *bool) void {
    switch (event) {
        .configure => {},
        .close => running.* = false,
    }
}
