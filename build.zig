const std = @import("std");
const Builder = std.build.Builder;
const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const scanner = ScanProtocolsStep.create(b);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    // Pass the maximum version implemented by your wayland server or client.
    // Requests, events, enums, etc. from newer versions will not be generated,
    // ensuring forwards compatibility with newer protocol xml.
    // This will also generate code for interfaces created using the provided
    // global interface, in this example wl_keyboard, wl_pointer, xdg_surface,
    // xdg_toplevel, etc. would be generated.
    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 1);

    const wayland = std.build.Pkg{
        .name = "wayland",
        .path = .{ .generated = &scanner.result },
    };

    const exe = b.addExecutable("hello-zig-wayland", "hello.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.step.dependOn(&scanner.step);
    exe.addPackage(wayland);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
