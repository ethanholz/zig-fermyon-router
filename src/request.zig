const std = @import("std");

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
