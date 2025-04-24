const std = @import("std");
const zmpl = @import("zmpl");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const microwave_dependency = b.dependency("microwave", .{});
    const datetime_dependency = b.dependency("datetime", .{});
    const httpz_dependency = b.dependency("httpz", .{});
    const zmpl_dependency = b.dependency("zmpl", .{
        .zmpl_templates_paths = try zmpl.templatesPaths(b.allocator, &.{
            .{
                .prefix = "views",
                .path = &.{b.pathFromRoot("src/views")},
            },
        }),
    });

    const microwave_module = microwave_dependency.module("microwave");
    const datetime_module = datetime_dependency.module("datetime");
    const httpz_module = httpz_dependency.module("httpz");
    const zmpl_module = zmpl_dependency.module("zmpl");

    const main_module = b.createModule(.{
        .root_source_file = b.path("./src/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    main_module.addImport("microwave", microwave_module);
    main_module.addImport("datetime", datetime_module);
    main_module.addImport("httpz", httpz_module);
    main_module.addImport("zmpl", zmpl_module);

    const main_artifact = b.addExecutable(.{
        .name = "ono",
        .root_module = main_module,
    });

    b.installArtifact(main_artifact);
}
