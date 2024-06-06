const std = @import("std");
const Allocator = std.mem.Allocator;
const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

const TcpServerError = error{InvalidAddress};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len != 2) {
        try stderr.print("Usage: {s} <address>\n", .{std.fs.path.basename(args[0])});
        return;
    }
    const addr_str = args[1];
    const address = try parseAddrString(addr_str);
    try echoServer(allocator, address);
}

fn echoServer(allocator: Allocator, address: std.net.Address) !void {
    var server = try address.listen(.{});
    defer server.deinit();

    var pool: std.Thread.Pool = undefined;
    try pool.init(.{ .allocator = allocator });
    defer pool.deinit();

    while (true) {
        const conn = try server.accept();
        try pool.spawn(spawnWrapper, .{ handleConnection, .{conn} });
    }
}

fn parseAddrString(addr: []const u8) !std.net.Address {
    var iter = std.mem.splitScalar(u8, addr, ':');

    const host = iter.next() orelse return TcpServerError.InvalidAddress;
    const port_str = iter.next() orelse return TcpServerError.InvalidAddress;
    if (iter.next() != null) return TcpServerError.InvalidAddress;

    const port = try std.fmt.parseInt(u16, port_str, 10);
    return std.net.Address.parseIp(host, port);
}

fn handleConnection(conn: std.net.Server.Connection) !void {
    defer conn.stream.close();
    var buf: [4096]u8 = undefined;

    try stdout.print("Accepted connection from {}\n", .{conn.address});

    const stream = conn.stream;

    while (true) {
        const n = try stream.read(&buf);
        if (n == 1) break;
        try stdout.print("{s}", .{buf[0..n]});
        _ = try stream.write(buf[0..n]);
    }
    try stdout.print("Close connection from {}\n", .{conn.address});
}

fn spawnWrapper(comptime f: anytype, args: anytype) void {
    @call(.auto, f, args) catch {};
}
