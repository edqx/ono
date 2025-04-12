const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const toml_dependency = b.dependency("toml", .{});
    const toml_module = toml_dependency.module("zig-toml");

    const main_module = b.createModule(.{
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    main_module.addImport("toml", toml_module);

    const main_artifact = b.addExecutable(.{
        .name = "ono",
        .root_module = main_module,
    });

    b.installArtifact(main_artifact);
}
