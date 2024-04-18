const std = @import("std");
const mime = @import("mime");

pub const HttpRequest = @import("request.zig").HttpRequest;
pub const HttpResponse = @import("response.zig").HttpResponse;

const serveFile = @import("static.zig").serveFile;

/// A function that handles an HTTP request.
pub const HttpHandlerFunc = *const fn (HttpRequest, *HttpResponse) void;

/// HandlerStruct
pub const HttpHandler = struct {
    handler: HttpHandlerFunc,
    methods: ?std.ArrayList(std.http.Method) = null,

    pub fn init(handler: HttpHandlerFunc) HttpHandler {
        return HttpHandler{ .handler = handler };
    }
};

pub const Router = struct {
    usingnamespace @import("static.zig");
    routes: std.StringArrayHashMap(HttpHandler),
    not_found_handler: HttpHandler,
    debug: bool = false,
    allocator: std.mem.Allocator,

    pub fn new(allocator: std.mem.Allocator) Router {
        const not_found_handler = HttpHandler.init(default_404_handler);
        return Router{
            .allocator = allocator,
            .routes = std.StringArrayHashMap(HttpHandler).init(allocator),
            .not_found_handler = not_found_handler,
        };
    }
    pub fn withDebug(self: Router, debug: bool) Router {
        return Router{ .allocator = self.allocator, .routes = self.routes, .not_found_handler = self.not_found_handler, .debug = debug };
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    pub fn addRoute(self: *Router, route: []const u8, handlerFunc: HttpHandlerFunc) !void {
        if (self.routes.get(route) != null) return;
        const handler = HttpHandler.init(handlerFunc);
        try self.routes.put(route, handler);
    }

    pub fn createStaticRoutes(self: *Router, files: std.fs.Dir) !void {
        var dir_iter = try files.walk(self.allocator);
        defer dir_iter.deinit();
        try self.addRoute("/", Router.serveFile);
        while (try dir_iter.next()) |entry| {
            const name = entry.path;
            if (entry.kind == std.fs.File.Kind.directory) {
                const concat = std.mem.concat(self.allocator, u8, &[_][]const u8{ "/", name, "/" }) catch |err| {
                    std.debug.print("Error formatting path: {any}\n", .{err});
                    return;
                };
                try self.addRoute(concat, Router.serveFile);
                continue;
            }
            const concat = std.mem.concat(self.allocator, u8, &[_][]const u8{ "/", name }) catch |err| {
                std.debug.print("Error formatting path: {any}\n", .{err});
                return;
            };
            try self.addRoute(concat, Router.serveFile);
        }
    }

    pub fn get(self: *Router, route: []const u8) !void {
        try self.method(route, std.http.Method.GET);
    }

    pub fn post(self: *Router, route: []const u8) !void {
        try self.method(route, std.http.Method.POST);
    }

    pub fn method(self: *Router, route: []const u8, met: std.http.Method) !void {
        const entry = self.routes.getEntry(route);
        if (entry == null) {
            return;
        }
        const mets = &entry.?.value_ptr.methods;
        if (mets.* == null) {
            mets.* = std.ArrayList(std.http.Method).init(self.allocator);
        }
        try mets.*.?.append(met);
    }

    pub fn methods(self: *Router, route: []const u8, mets: anytype) !void {
        const entry = self.routes.getEntry(route);
        if (entry == null) {
            return;
        }
        const internal_methods = &entry.?.value_ptr.methods;
        if (internal_methods.* == null) {
            internal_methods.* = std.ArrayList(std.http.Method).init(self.allocator);
        }
        inline for (mets) |met| {
            if (@TypeOf(met) != std.http.Method) {
                const item = std.http.Method.parse(met);
                try internal_methods.*.?.append(@enumFromInt(item));
            } else {
                try internal_methods.*.?.append(met);
            }
        }
    }

    pub fn routeRequest(self: *Router) !void {
        var envMap = try std.process.getEnvMap(self.allocator);
        defer envMap.deinit();
        const route = envMap.get("PATH_INFO").?;
        var handler = self.routes.get(route) orelse self.not_found_handler;
        const log = std.log.scoped(.request);
        log.info("Request for {s}", .{route});
        var resp = HttpResponse.init(&self.allocator);
        const req = HttpRequest.init(&self.allocator, envMap);
        // TODO: This is less than ideal, might want to look at using a context to pass and chain middlewares.
        if (handler.handler == self.not_found_handler.handler) {
            const last = route[route.len - 1];
            if (last != '/') {
                const concat = std.mem.concat(self.allocator, u8, &[_][]const u8{ route, "/" }) catch |err| {
                    std.debug.print("Error formatting path: {any}\n", .{err});
                    return;
                };
                handler = self.routes.get(concat) orelse self.not_found_handler;
                if (handler.handler != self.not_found_handler.handler) {
                    resp.addHeader("Location", concat) catch |err| {
                        std.debug.print("Error writing to response: {any}\n", .{err});
                    };
                    resp.writeHeader(std.http.Status.moved_permanently) catch |err| {
                        std.debug.print("Error writing to response: {any}\n", .{err});
                    };
                    return;
                }
            }
        }
        log.debug("handler methods: {any}", .{handler.methods});
        log.debug("handler: {any}", .{handler.handler});
        outer: {
            if (handler.methods != null) {
                const met = std.http.Method.parse(req.method().?);
                for (handler.methods.?.items) |item| {
                    if (met == @intFromEnum(item)) {
                        break :outer;
                    }
                }
                resp.writeHeader(std.http.Status.method_not_allowed) catch |err| {
                    std.debug.print("Error writing to response: {any}\n", .{err});
                };
                return;
            }
        }
        resp.log.debug("Calling handler for {s}", .{route});
        handler.handler(req, &resp);
        if (!resp.written) {
            resp.writeHeaders() catch |err| {
                std.debug.panic("Error writing headers to response: {any}", .{err});
            };
        }
        resp.log.debug("Finished handling request for {s}", .{route});
    }

    pub fn with_404_handler(self: *Router, handlerFunc: HttpHandlerFunc) void {
        const handler = HttpHandler.init(handlerFunc);
        self.not_found_handler = handler;
    }

    pub fn default_404_handler(_: HttpRequest, response: *HttpResponse) void {
        response.addHeader("content-type", "text/plain") catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };
        response.writeHeader(std.http.Status.not_found) catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };
        std.debug.print("{s}: {s}", .{ response.headers.items[0].name, response.headers.items[0].value });
        _ = response.write("404 Not Found") catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };
    }
};
