# zig-fermyon-router
The purpose of this project is to provide a simple, Go-like interface for building applications on Fermyon Spin. This is achieved by leveraging WAGI (with plans to use the Spin WIT Worlds in the future) to handle requests and build an easy-to-use interface.

## Requirements
- Zig 0.12.0
- Fermyon Spin

**Note**: You can also try this out using Nix but cloning the repo and then running `nix develop`

## Getting Started
0. Add your imports
```zig
const fermyon_router = @import("zig-fermyon-router");
const HttpRequest = fermyon_router.HttpRequest;
const HttpResponse = fermyon_router.HttpResponse;
const Router = fermyon_router.Router;
```
1. Build a route handler like.
```zig
pub fn testHandler(_: HttpRequest, response: *HttpResponse) void {
    _ = response.write("Hello, world!") catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
}
```
2. Add the route to the router.
```zig
pub fn main() !void {
    var allocator = std.heap.wasm_allocator;
    var router = Router.new(allocator);
    defer router.deinit();

    try router.addRoute("/api/testing", testHandler);
    try router.routeRequest();
}
```
3. Add the following to your build.zig to build your router and generate your `spin.toml`:
```zig
const std = @import("std");
const spin = @import("zig-fermyon-router");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{ .os_tag = .wasi, .cpu_arch = .wasm32 });
    const optimize = b.standardOptimizeOption(.{});

    const fsr = b.dependency("zig-fermyon-router", .{});

    const exe = b.addExecutable(.{
        .name = "<name of your executable>",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("zig-fermyon-router", fsr.module("zig-fermyon-router"));

    spin.generateSpinTOML(b, exe, .{
        .author = "<Your name>",
        .description = "<Your project description>"
        .version = "<Your version>"
    });
    b.installArtifact(exe);
}
```
4. Run your app with Fermyon Spin:
```bash
cd zig-out
spin up
```
