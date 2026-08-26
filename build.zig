const std = @import("std");
const Build = std.Build;
pub fn build(b:*Build) void {
  const target = b.standardTargetOptions(.{});
  const optimize = b.standardOptimizeOption(.{});
  const lib = b.addLibrary(.{
    .name = "ArrayListManaged",
    .root_module = b.createModule(.{
      .root_source_file = b.path("src/ArrayListManaged.zig"),
      .target = target,
      .optimize = optimize
    }),
    .linkage = .dynamic,
    .version = .{
      .major = 0,
      .minor = 1,
      .patch = 0,
    },
  });
  b.installArtifact(lib);
}