const std = @import("std");

const toml =
    \\spin_manifest_version = 2
    \\
    \\[application]
    \\name = "{s}"
    \\version = "{s}"
    \\description = "{s}"
    \\authors = ["{s}"]
    \\
    \\[application.trigger.http]
    \\base = "/"
    \\
    \\[[trigger.http]]
    \\id = "trigger-fermyon-router"
    \\component = "{s}"
    \\route = "/..."
    \\executor = {{ type = "wagi" }}
    \\
    \\[component.{s}]
    \\source = "bin/{s}.wasm"
;

pub const Options = struct {
    version: []const u8,
    description: []const u8,
    author: []const u8,
};

/// This function generates a `spin.toml`
pub fn generateSpinTOML(b: *std.Build, exe_build_step: *std.Build.Step.Compile, options: Options) void {
    const name = exe_build_step.name;
    const allocator = b.allocator;
    const str = std.fmt.allocPrint(allocator, toml, .{ name, options.version, options.description, options.author, name, name, name }) catch {
        @panic("Failed to generate toml");
    };
    defer allocator.free(str);
    const writeFile = b.addWriteFile("spin.toml", str);
    b.installDirectory(.{
        .source_dir = writeFile.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&writeFile.step);
}

pub fn build(b: *std.Build) void {
    // Set the target to wasm32-wasi
    const target = b.resolveTargetQuery(.{ .os_tag = .wasi, .cpu_arch = .wasm32 });
    const optimize = b.standardOptimizeOption(.{});
    // set the mode to the target and optimize
    const mode = .{ .target = target, .optimize = optimize };

    // Add the MIME type library
    const mime = b.dependency("mime", mode);

    // Create a module for the router
    _ = b.addModule("zig-fermyon-router", .{
        .root_source_file = .{ .path = "src/root.zig" },
    });
    _ = b.addModule("fermyon-tools", .{
        .root_source_file = .{ .path = "tools/generate-spin.zig" },
    });

    // Build the main executable for testing
    const exe = b.addExecutable(.{
        .name = "zig-fermyon-router",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("mime", mime.module("mime"));

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig buid`).
    b.installArtifact(exe);

    // Adds a step to generate the spin.toml file
    generateSpinTOML(b, exe, .{
        .author = "Ethan Holz",
        .description = "A Fermyon Spin Router for Zig",
        .version = "v0.0.2",
    });
    // other.step.dependOn(&exe.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
