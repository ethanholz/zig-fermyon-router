const std = @import("std");

const fermyon_router = @import("root.zig");
const HttpRequest = fermyon_router.HttpRequest;
const HttpResponse = fermyon_router.HttpResponse;
const Router = fermyon_router.Router;
const serveFile = fermyon_router.serveFile;

pub fn testHandler(_: HttpRequest, response: *HttpResponse) void {
    response.addHeader("content-type", "text/plain") catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    response.writeHeader(std.http.Status.ok) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    _ = response.write("Hello, world!") catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
}

const Body = struct {
    name: []const u8,
};

pub fn testPost(req: HttpRequest, response: *HttpResponse) void {
    const allocator = std.heap.wasm_allocator;
    const method = req.method().?;
    const contentType = req.contentType().?;
    const contentLength = req.contentLength() catch {
        return;
    };
    std.debug.print("Method: {s}\n", .{method});
    std.debug.print("Content-Type: {s}\n", .{contentType});
    std.debug.print("Content-Length: {d}\n", .{contentLength});
    var env = req.envVars.iterator();
    while (env.next()) |item| {
        std.debug.print("{s}: {s}\n", .{ item.key_ptr.*, item.value_ptr.* });
    }
    // const writer = response.writer();
    const body = req.reader.readAllAlloc(allocator, 1) catch {
        // const errMsg = "Error reading request body";
        // errorResponse(response, std.http.Status.internal_server_error, errMsg);
        response.writeHeader(std.http.Status.internal_server_error) catch {};
        return;
    };
    const decoded = std.json.parseFromSlice(Body, allocator, body, .{}) catch |err| {
        std.debug.print("Error parsing JSON: {any}\n", .{err});
        return;
    };
    defer decoded.deinit();
    const name = decoded.value.name;

    response.addHeader("content-type", "text/plain") catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    response.writeHeader(std.http.Status.ok) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
    response.print("Hello, {s}!", .{name}) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
}

pub fn main() !void {
    var allocator = std.heap.wasm_allocator;
    var router = Router.new(allocator);
    defer router.deinit();

    try router.addRoute("/api/testing", testHandler);
    try router.addRoute("/hello", testPost);
    try router.createStaticRoutes(std.fs.cwd());
    try router.routeRequest(&allocator);
}
