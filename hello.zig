const std = @import("std");
const os = std.os;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const c = @cImport(@cInclude("linux/input-event-codes.h"));

const Context = struct {
    shm: ?*wl.Shm = null,
    compositor: ?*wl.Compositor = null,
    wm_base: ?*xdg.WmBase = null,

    xdg_toplevel: ?*xdg.Toplevel = null,
    seat: ?*wl.Seat = null,
};

pub fn main() anyerror!void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var context = Context{};

    registry.setListener(*Context, registryListener, &context);
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

        break :blk try pool.createBuffer(0, width, height, stride, wl.Shm.Format.argb8888);
    };
    defer buffer.destroy();

    const surface = try compositor.createSurface();
    defer surface.destroy();
    const xdg_surface = try wm_base.getXdgSurface(surface);
    defer xdg_surface.destroy();
    context.xdg_toplevel = try xdg_surface.getToplevel();
    defer context.xdg_toplevel.?.destroy();

    var running = true;

    xdg_surface.setListener(*wl.Surface, xdgSurfaceListener, surface);
    context.xdg_toplevel.?.setListener(*bool, xdgToplevelListener, &running);

    surface.commit();
    _ = try display.roundtrip();

    surface.attach(buffer, 0, 0);
    surface.commit();

    while (running) _ = try display.dispatch();
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, wl.Compositor.getInterface().name) == 0) {
                context.compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Seat.getInterface().name) == 0) {
                context.seat = registry.bind(global.name, wl.Seat, 1) catch return;
                context.seat.?.setListener(*Context, seatListener, context);
            } else if (std.cstr.cmp(global.interface, wl.Shm.getInterface().name) == 0) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.cstr.cmp(global.interface, xdg.WmBase.getInterface().name) == 0) {
                context.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
            }
        },
        .global_remove => {},
    }
}

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, context: *Context) void {
    switch (event) {
        .capabilities => |data| {
            if (data.capabilities.pointer) {
                const pointer = seat.getPointer() catch return;
                pointer.setListener(*Context, pointerListener, context);
            }
        },
        .name => {},
    }
}

fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, context: *Context) void {
    switch (event) {
        .enter => {},
        .leave => {},
        .motion => {},
        .button => |data| {
            if (data.button == c.BTN_LEFT and data.state == wl.Pointer.ButtonState.pressed) {
                context.xdg_toplevel.?.move(context.seat.?, data.serial);
            }
        },
        .frame => {},
        .axis => {},
        .axis_source => {},
        .axis_stop => {},
        .axis_discrete => {},
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
