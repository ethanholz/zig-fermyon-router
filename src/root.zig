const std = @import("std");
const mime = @import("mime");

/// A function that handles an HTTP request.
pub const HttpHandler = *const fn (HttpRequest, *HttpResponse) void;

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

    pub fn init(allocator: *std.mem.Allocator) HttpResponse {
        return HttpResponse{ .headers = std.ArrayList(std.http.Header).init(allocator.*) };
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
    }

    pub fn writeHeader(self: HttpResponse, status: std.http.Status) !void {
        try self.writer.print("Status: {d} {s}\n", .{ @intFromEnum(status), status.phrase().? });
        for (self.headers.items) |header| {
            try self.writer.print("{s}: {s}\n", .{ header.name, header.value });
        }
        try self.writer.print("\n", .{});
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

    pub fn writeHeaders(self: HttpResponse) !void {
        for (self.headers.items) |header| {
            try self.writer.print("{s}: {s}\n", .{ header.name, header.value });
        }
    }

    pub fn write(self: HttpResponse, comptime data: []const u8) !usize {
        return try self.writer.write(data);
    }

    pub fn print(self: HttpResponse, comptime data: []const u8, args: anytype) !void {
        try self.writer.print(data, args);
    }
};

pub const Router = struct {
    routes: std.StringArrayHashMap(HttpHandler),
    not_found_handler: HttpHandler = Router.default_404_handler,

    pub fn new(allocator: std.mem.Allocator) Router {
        return Router{
            .routes = std.StringArrayHashMap(HttpHandler).init(allocator),
        };
    }

    pub fn deinit(self: *Router) void {
        self.routes.deinit();
    }

    pub fn addRoute(self: *Router, route: []const u8, handler: HttpHandler) !void {
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

    pub fn routeRequest(self: *Router, allocator: *std.mem.Allocator) !void {
        var envMap = try std.process.getEnvMap(allocator.*);
        defer envMap.deinit();
        const route = envMap.get("PATH_INFO").?;
        // for (self.routes.keys()) |key| {
        //     std.debug.print("key: {s}\n", .{key});
        // }
        // std.debug.print("route: {s}\n", .{route});
        var handler = self.routes.get(route) orelse self.not_found_handler;
        var resp = HttpResponse.init(allocator);
        const req = HttpRequest.init(allocator, envMap);
        // TODO: This is less than ideal, might want to look at using a context to pass and chain middlewares.
        if (handler == self.not_found_handler) {
            const last = route[route.len - 1];
            if (last != '/') {
                const concat = std.mem.concat(allocator.*, u8, &[_][]const u8{ route, "/" }) catch |err| {
                    std.debug.print("Error formatting path: {any}\n", .{err});
                    return;
                };
                handler = self.routes.get(concat) orelse self.not_found_handler;
                if (handler != self.not_found_handler) {
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
        handler(req, &resp);
    }

    pub fn with_404_handler(self: *Router, handler: HttpHandler) void {
        self.not_found_handler = handler;
    }

    pub fn default_404_handler(_: HttpRequest, response: *HttpResponse) void {
        // const writer = response.writer();
        response.print("Status: 404 Not Found\n", .{}) catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };
        response.print("content-type: text/plain\n\n", .{}) catch |err| {
            std.debug.print("Error writing to response: {any}\n", .{err});
        };
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
    // const strip_ext = std.mem.trimLeft(u8, ext, ".");
    // const content_type = guessContentType(strip_ext) orelse "text/plain";
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
