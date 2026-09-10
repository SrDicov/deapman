const std = @import("std");

// deapman-thin: content-hash helper for deapman (inventory, verify, thin, gc).
// Static musl binary: zig build -Doptimize=ReleaseSafe -Dtarget=x86_64-linux-musl
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "deapman-thin",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run deapman-thin");
    run_step.dependOn(&run_cmd.step);
}
