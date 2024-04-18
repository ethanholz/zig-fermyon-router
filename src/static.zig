const std = @import("std");
const mime = @import("mime");
const HttpRequest = @import("root.zig").HttpRequest;
const HttpResponse = @import("root.zig").HttpResponse;

pub fn serveFile(req: HttpRequest, response: *HttpResponse) void {
    const allocator = response.responseAllocator();
    const path = req.pathInfo().?;
    const strip = std.mem.trimLeft(u8, path, "/");
    const last = path[path.len - 1];
    if (last == '/') {
        response.addHeaders(.{
            .{ "content-type", "text/html" },
            .{ "cache-control", "public, max-age=60" },
        }) catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };
        response.writeHeader(std.http.Status.ok) catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };

        const full = std.mem.concat(allocator, u8, &[_][]const u8{ strip, "index.html" }) catch |err| {
            std.debug.print("Error formatting path: {any}\n", .{err});
            return;
        };
        // std.debug.print("full: {s}\n", .{full});
        const file = std.fs.cwd().openFile(full, .{}) catch |err| {
            std.debug.print("Error opening file: {any}\n", .{err});
            return;
        };
        const reader = file.reader();
        const contents = reader.readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
            std.debug.print("Error reading file: {any}\n", .{err});
            return;
        };
        response.print("{s}", .{contents}) catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };

        return;
    }
    const ext = std.fs.path.extension(path);
    const content_type = mime.extension_map.get(ext) orelse mime.Type.@"text/plain";
    response.addHeaders(.{
        .{ "content-type", @tagName(content_type) },
        .{ "cache-control", "public, max-age=60" },
    }) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    response.writeHeader(std.http.Status.ok) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    const file = std.fs.cwd().openFile(strip, .{}) catch |err| {
        std.debug.print("Error opening file: {any}\n", .{err});
        return;
    };
    const reader = file.reader();
    const contents = reader.readAllAlloc(allocator, std.math.maxInt(usize)) catch |err| {
        std.debug.print("Error reading file: {any}\n", .{err});
        return;
    };
    response.print("{s}", .{contents}) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    return;
}
