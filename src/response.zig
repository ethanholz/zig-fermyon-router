const std = @import("std");

/// A response to an HTTP request.
pub const HttpResponse = struct {
    comptime log: type = std.log.scoped(.response),
    writer: std.io.AnyWriter = std.io.getStdOut().writer().any(),
    headers: std.ArrayList(std.http.Header),
    allocator: *std.mem.Allocator,
    written: bool = false,

    pub fn init(allocator: *std.mem.Allocator) HttpResponse {
        var headers = std.ArrayList(std.http.Header).init(allocator.*);
        // Set the first header as the response status.
        headers.append(std.http.Header{ .name = "Status", .value = "200 OK" }) catch |err| {
            std.debug.panic("Error writing to response: {any}\n", .{err});
        };
        return HttpResponse{ .headers = headers, .allocator = allocator };
    }

    pub fn responseAllocator(self: *HttpResponse) std.mem.Allocator {
        return self.allocator.*;
    }

    pub fn deinit(self: *HttpResponse) void {
        self.headers.deinit();
    }

    pub fn writeHeader(self: *HttpResponse, status: std.http.Status) !void {
        const value = std.fmt.allocPrint(self.allocator.*, "{d} {s}", .{ @intFromEnum(status), status.phrase().? }) catch |err| {
            std.debug.panic("Error formatting status: {any}\n", .{err});
        };
        self.headers.items[0] = std.http.Header{ .name = "Status", .value = value };
        try self.writeHeaders();
    }

    pub fn writeHeaders(self: *HttpResponse) !void {
        if (self.written) {
            return;
        }
        for (self.headers.items) |header| {
            try self.writer.print("{s}: {s}\n", .{ header.name, header.value });
            self.log.debug("{s}: {s}", .{ header.name, header.value });
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
                self.log.err("Error writing to response: {any}", .{err});
                // std.debug.print("Error writing to response: {any}\n", .{err});
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
                std.log.err("Error writing to response: {any}", .{err});
            };
        }
        try self.writeHeaders();
        try self.writer.print(data, args);
    }
};
