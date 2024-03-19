const std = @import("std");

const toml =
    \\spin_manifest_version = 2
    \\
    \\[application]
    \\name = "{s}"
    \\version = "0.0.1"
    \\description = "A WAGI implementation of fermyon-router"
    \\authors = ["Ethan Holz"]
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

fn buildSpinToml(name: []u8, output: []u8) !void {
    const path = try std.fs.cwd().createFile(output, .{});
    defer path.close();
    const writer = path.writer();
    try std.fmt.format(writer, toml, .{ name, name, name, name });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer _ = arena.reset(.free_all);
    const args = try std.process.argsAlloc(arena.allocator());
    if (args.len < 4) {
        std.debug.print("Usage: build_spin_toml <name> -o <output>\n", .{});
        return;
    }
    const name = args[1];
    const output = args[3];
    _ = std.fs.cwd().statFile(output) catch {
        try buildSpinToml(name, output);
    };
}
