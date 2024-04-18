const std = @import("std");

const fermyon_router = @import("zig-fermyon-router");
const HttpRequest = fermyon_router.HttpRequest;
const HttpResponse = fermyon_router.HttpResponse;
const Router = fermyon_router.Router;
const serveFile = fermyon_router.serveFile;

pub fn testHandler(_: HttpRequest, response: *HttpResponse) void {
    response.log.info("This is a log", .{});
    _ = response.write("Hello, world!") catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
}

pub fn addHeader(_: HttpRequest, response: *HttpResponse) void {
    response.addHeader("content-type", "application/json") catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
}

const Body = struct {
    name: []const u8,
};

pub fn testPost(req: HttpRequest, response: *HttpResponse) void {
    const allocator = response.responseAllocator();
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
    const body = req.reader.readAllAlloc(allocator, 1) catch { // const errMsg = "Error reading request body";
        response.writeHeader(std.http.Status.internal_server_error) catch {};
        return;
    };
    const decoded = std.json.parseFromSlice(Body, allocator, body, .{}) catch |err| {
        std.debug.print("Error parsing JSON: {any}\n", .{err});
        return;
    };
    defer decoded.deinit();
    const name = decoded.value.name;

    response.print("Hello, {s}!", .{name}) catch |err| {
        std.debug.print("Error writing to response: {any}\n", .{err});
    };
}

pub const debug = true;

pub const std_options = .{
    .log_level = if (debug) .debug else .info,
};

pub fn main() !void {
    const allocator = std.heap.wasm_allocator;
    var router = Router.new(allocator);
    defer router.deinit();

    // try router.addRoute("/api/testing", testHandler);
    try router.addRoute("/api/testing", testHandler);
    try router.methods("/api/testing", .{
        "POST",
        std.http.Method.GET,
    });
    try router.addRoute("/hello", testPost);
    try router.post("/hello");
    try router.routeRequest();
}
