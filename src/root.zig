const std = @import("std");
const mime = @import("mime");

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

/// A request to an HTTP server.
pub const HttpRequest = struct {
    reader: std.io.AnyReader = std.io.getStdIn().reader().any(),
    envVars: std.process.EnvMap,

    pub fn init(_: *std.mem.Allocator, env: std.process.EnvMap) HttpRequest {
        return HttpRequest{ .envVars = env };
    }

    pub fn method(self: HttpRequest) ?[]const u8 {
        return self.envVars.get("REQUEST_METHOD");
    }

    pub fn contentType(self: HttpRequest) ?[]const u8 {
        return self.envVars.get("HTTP_CONTENT_TYPE");
    }

    pub fn contentLength(self: HttpRequest) !usize {
        const content_length = self.envVars.get("CONTENT_LENGTH");
        if (content_length == null) {
            return 0;
        }
        return try std.fmt.parseInt(usize, content_length.?, 10);
    }

    pub fn pathInfo(self: HttpRequest) ?[]const u8 {
        return self.envVars.get("PATH_INFO");
    }
};

/// A response to an HTTP request.
pub const HttpResponse = struct {
    writer: std.io.AnyWriter = std.io.getStdOut().writer().any(),
    headers: std.ArrayList(std.http.Header),
    written: bool = false,
    debug: bool = false,

    pub fn init(allocator: *std.mem.Allocator, debug: bool) HttpResponse {
        var headers = std.ArrayList(std.http.Header).init(allocator.*);
        // Set the first header as the response status.
        headers.append(std.http.Header{ .name = "Status", .value = "200 OK" }) catch |err| {
            std.debug.panic("Error writing to response: {any}\n", .{err});
        };
        return HttpResponse{ .headers = headers, .debug = debug };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
    }

    pub fn writeHeader(self: *HttpResponse, status: std.http.Status) !void {
        const allocator = std.heap.wasm_allocator;
        const value = std.fmt.allocPrint(allocator, "{d} {s}", .{ @intFromEnum(status), status.phrase().? }) catch |err| {
            std.debug.panic("Error formatting status: {any}\n", .{err});
        };
        self.headers.items[0] = std.http.Header{ .name = "Status", .value = value };
        try self.writeHeaders();
    }

    fn writeHeaders(self: *HttpResponse) !void {
        if (self.written) {
            return;
        }
        for (self.headers.items) |header| {
            try self.writer.print("{s}: {s}\n", .{ header.name, header.value });
            if (self.debug) {
                std.debug.print("{s}: {s}\n", .{ header.name, header.value });
            }
        }
        try self.writer.print("\n", .{});
        self.written = true;
    }

    pub fn addHeader(self: *HttpResponse, key: []const u8, value: []const u8) !void {
        try self.headers.append(std.http.Header{ .name = key, .value = value });
    }

    pub fn addHeaders(self: *HttpResponse, headers: anytype) !void {
        inline for (headers) |header| {
            self.addHeader(header.@"0", header.@"1") catch |err| {
                std.debug.print("Error writing to response: {any}\n", .{err});
            };
        }
    }

    pub fn write(self: *HttpResponse, comptime data: []const u8) !usize {
        try self.writeHeaders();
        return try self.writer.write(data);
    }

    pub fn print(self: *HttpResponse, comptime data: []const u8, args: anytype) !void {
        outer: {
            if (!self.written) {
                const headers = self.headers;
                for (headers.items) |header| {
                    if (std.mem.eql(u8, header.name, "content-type")) {
                        break :outer;
                    }
                }
            }
            // Set the content type to text/plain if it hasn't been set.
            self.addHeader("content-type", "text/plain") catch |err| {
                std.debug.print("Error writing to response: {any}\n", .{err});
            };
        }
        try self.writeHeaders();
        try self.writer.print(data, args);
    }
};

pub const Router = struct {
    routes: std.StringArrayHashMap(HttpHandler),
    not_found_handler: HttpHandler,
    debug: bool = false,

    pub fn new(allocator: std.mem.Allocator) Router {
        const not_found_handler = HttpHandler.init(default_404_handler);
        return Router{
            .routes = std.StringArrayHashMap(HttpHandler).init(allocator),
            .not_found_handler = not_found_handler,
        };
    }
    pub fn withDebug(self: Router, debug: bool) Router {
        return Router{ .routes = self.routes, .not_found_handler = self.not_found_handler, .debug = debug };
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
        // try self.add_route("/", serve_file);
        // var dir_iter = files.iterate();
        var dir_iter = try files.walk(std.heap.wasm_allocator);
        defer dir_iter.deinit();
        try self.addRoute("/", serveFile);
        while (try dir_iter.next()) |entry| {
            // const name = entry.basename;
            const name = entry.path;
            // std.debug.print("name: {s}\n", .{name});
            // const name = entry.name;
            if (entry.kind == std.fs.File.Kind.directory) {
                const concat = std.mem.concat(std.heap.wasm_allocator, u8, &[_][]const u8{ "/", name, "/" }) catch |err| {
                    std.debug.print("Error formatting path: {any}\n", .{err});
                    return;
                };
                // std.debug.print("concat: {s}\n", .{concat});
                try self.addRoute(concat, serveFile);
                continue;
            }
            const concat = std.mem.concat(std.heap.wasm_allocator, u8, &[_][]const u8{ "/", name }) catch |err| {
                std.debug.print("Error formatting path: {any}\n", .{err});
                return;
            };
            try self.addRoute(concat, serveFile);
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
            mets.* = std.ArrayList(std.http.Method).init(std.heap.wasm_allocator);
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
            internal_methods.* = std.ArrayList(std.http.Method).init(std.heap.wasm_allocator);
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

    pub fn routeRequest(self: *Router, allocator: *std.mem.Allocator) !void {
        var envMap = try std.process.getEnvMap(allocator.*);
        defer envMap.deinit();
        const route = envMap.get("PATH_INFO").?;
        var handler = self.routes.get(route) orelse self.not_found_handler;
        var resp = HttpResponse.init(allocator, self.debug);
        const req = HttpRequest.init(allocator, envMap);
        // TODO: This is less than ideal, might want to look at using a context to pass and chain middlewares.
        if (handler.handler == self.not_found_handler.handler) {
            const last = route[route.len - 1];
            if (last != '/') {
                const concat = std.mem.concat(allocator.*, u8, &[_][]const u8{ route, "/" }) catch |err| {
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
        if (self.debug) {
            std.debug.print("handler: {any}\n", .{handler.methods});
        }
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
        handler.handler(req, &resp);
        if (!resp.written) {
            resp.writeHeaders() catch |err| {
                std.debug.panic("Error writing headers to response: {any}", .{err});
            };
        }
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

pub fn serveFile(req: HttpRequest, response: *HttpResponse) void {
    const allocator = std.heap.wasm_allocator;
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
