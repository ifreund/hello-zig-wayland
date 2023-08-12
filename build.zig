const std = @import("std");
const Builder = std.build.Builder;
const Scanner = @import("deps/zig-wayland/build.zig").Scanner;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");

    // Pass the maximum version implemented by your wayland server or client.
    // Requests, events, enums, etc. from newer versions will not be generated,
    // ensuring forwards compatibility with newer protocol xml.
    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_shm", 1);
    scanner.generate("xdg_wm_base", 1);

    const exe = b.addExecutable(.{
        .name = "hello-zig-wayland",
        .root_source_file = .{ .path = "hello.zig" },
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("wayland", wayland);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");

    // TODO: remove when https://github.com/ziglang/zig/issues/131 is implemented
    scanner.addCSource(exe);

    b.installArtifact(exe);
}
