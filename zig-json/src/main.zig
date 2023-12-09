const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const JsonError = error{SyntaxError} || std.fmt.ParseFloatError || PeekStreamError;

const ValueMap = std.StringArrayHashMap(Value);
const ValueArray = std.ArrayList(Value);
const String = std.ArrayList(u8);

const Value = union(enum) {
    Null,
    Object: ValueMap,
    Array: ValueArray,
    String: String,
    Number: f64,
    Bool: bool,

    pub fn stringify(self: @This(), a: Allocator, w: anytype) JsonError!void {
        switch (self) {
            .Object => |v| {
                try w.writeByte('{');
                for (v.keys(), 0..) |key, i| {
                    if (i > 0) try w.writeByte(',');
                    var bytes = std.ArrayList(u8).init(a);
                    defer bytes.deinit();
                    try bytes.writer().writeAll(key);
                    try (Value{ .String = bytes }).stringify(a, w);
                    try w.writeByte(':');
                    try v.get(key).?.stringify(a, w);
                }
                try w.writeByte('}');
            },
            .Array => |v| {
                try w.writeByte('[');
                for (v.items, 0..) |value, i| {
                    if (i > 0) try w.writeByte(',');
                    try value.stringify(a, w);
                }
                try w.writeByte(']');
            },
            .Bool => |v| try w.writeAll(if (v) "true" else "false"),
            .Number => |v| try w.w.print("{}", .{v}),
            .String => |v| {
                try w.writeByte('"');
                for (v.items) |c| {
                    switch (c) {
                        '"' => try w.writeAll("\\\""),
                        '\\' => try w.writeAll("\\\\"),
                        '\n' => try w.writeAll("\\n"),
                        '\r' => try w.writeAll("\\r"),
                        else => try w.writeByte(c),
                    }
                }
                try w.writeByte('"');
            },
            .Null => try w.writeByte("null"),
        }
    }

    pub fn deinit(self: *Value) void {
        switch (self.*) {
            .Object => |*v| {
                var iter = v.iterator();
                while (iter.next()) |item| {
                    v.allocator.free(item.key_ptr.*);
                    item.value_ptr.deinit();
                }
                v.deinit();
            },
            .Array => |v| {
                for (v.items) |*item| {
                    item.deinit();
                }
                v.deinit();
            },
            .String => |v| v.deinit(),
            else => {},
        }
    }
};

fn isWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r' => true,
        else => false,
    };
}

fn skipWhitespace(s: *PeekStream) JsonError!void {
    const r = s.reader();
    while (true) {
        const byte = r.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (!isWhitespace(byte)) {
            try s.putBackByte(byte);
            break;
        }
    }
}

fn parseObject(allocator: Allocator, s: *PeekStream) JsonError!ValueMap {
    const r = s.reader();
    var byte = try r.readByte();
    assert(byte == '{');

    var m = ValueMap.init(allocator);
    errdefer m.deinit();

    // empty object
    try skipWhitespace(s);
    byte = try r.readByte();
    if (byte == '}') {
        return m;
    }
    try s.putBackByte(byte);

    while (true) {
        try parseObjectKeyValue(allocator, s, &m);
        try skipWhitespace(s);
        byte = try r.readByte();
        if (byte == '}') break;
        if (byte != ',') return JsonError.SyntaxError;
    }
    return m;
}

fn parseObjectKeyValue(allocator: Allocator, s: *PeekStream, m: *ValueMap) JsonError!void {
    const r = s.reader();
    try skipWhitespace(s);
    var key = try parseString(allocator, s);
    defer key.deinit();
    try skipWhitespace(s);
    var byte = try r.readByte();
    if (byte != ':') return JsonError.SyntaxError;
    try skipWhitespace(s);
    const value = try parseImpl(allocator, s);
    try m.put(try key.toOwnedSlice(), value);
}

fn parseArray(allocator: Allocator, s: *PeekStream) JsonError!ValueArray {
    const r = s.reader();
    var byte = try r.readByte();
    assert(byte == '[');

    var m = ValueArray.init(allocator);
    errdefer m.deinit();

    // empty array
    try skipWhitespace(s);
    byte = try r.readByte();
    if (byte == ']') {
        return m;
    }
    try s.putBackByte(byte);

    while (true) {
        try skipWhitespace(s);
        const value = try parseImpl(allocator, s);
        try m.append(value);
        try skipWhitespace(s);
        byte = try r.readByte();
        if (byte == ']') break;
        if (byte != ',') return JsonError.SyntaxError;
    }
    return m;
}

fn parseString(allocator: Allocator, s: *PeekStream) JsonError!String {
    const r = s.reader();
    var byte = try r.readByte();
    if (byte != '"') return JsonError.SyntaxError;
    var buf = std.ArrayList(u8).init(allocator);
    errdefer buf.deinit();
    while (true) {
        byte = try r.readByte();
        if (byte == '\\') {
            byte = switch (try r.readByte()) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => unreachable,
            };
        } else if (byte == '"') {
            break;
        }
        try buf.append(byte);
    }
    return buf;
}

fn parseTrue(s: *PeekStream) JsonError!bool {
    var buf = [_]u8{0} ** 4;
    const nbytes = try s.read(&buf);
    return if (nbytes == 4 and std.mem.eql(u8, &buf, "true")) true else JsonError.SyntaxError;
}

fn parseFalse(s: *PeekStream) JsonError!bool {
    var buf = [_]u8{0} ** 5;
    const nbytes = try s.read(&buf);
    return if (nbytes == 5 and std.mem.eql(u8, &buf, "false")) false else JsonError.SyntaxError;
}

fn parseNull(s: *PeekStream) JsonError!void {
    var buf = [_]u8{0} ** 4;
    const nbytes = try s.read(&buf);
    return if (nbytes == 4 and std.mem.eql(u8, &buf, "null")) {} else JsonError.SyntaxError;
}

fn parseNumber(allocator: Allocator, br: anytype) JsonError!f64 {
    const r = br.reader();
    var buf = std.ArrayList(u8).init(allocator);
    defer buf.deinit();
    while (true) {
        const byte = r.readByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        switch (byte) {
            '0'...'9', '-', 'e', '.' => |v| try buf.append(v),
            else => |v| {
                try br.putBackByte(v);
                break;
            },
        }
    }
    return try std.fmt.parseFloat(f64, buf.items);
}

pub fn peekByte(s: *PeekStream) JsonError!u8 {
    const r = s.reader();
    const byte = try r.readByte();
    try s.putBackByte(byte);
    return byte;
}

pub fn peekBytes(s: *PeekStream, comptime len: usize) JsonError![usize]u8 {
    const r = s.reader();
    var buf = [len]u8{};
    const byte = try r.read(&buf);
    try s.putBack(&buf[0..byte]);
    return buf;
}

const peek_size = 2;
const PeekStream = std.io.PeekStream(std.fifo.LinearFifoBufferType{ .Static = peek_size }, std.io.StreamSource.Reader);
const PeekStreamError = PeekStream.Reader.NoEofError || error{OutOfMemory};

fn peekStream(s: *std.io.StreamSource) PeekStream {
    return std.io.peekStream(peek_size, s.reader());
}

pub fn parse(allocator: Allocator, source: *std.io.StreamSource) JsonError!Value {
    var stream = peekStream(source);
    const val = try parseImpl(allocator, &stream);
    try skipWhitespace(&stream);
    const res = stream.reader().readByte();
    if (res != error.EndOfStream) {
        return JsonError.SyntaxError;
    }
    return val;
}

pub fn parseJsonString(allocator: Allocator, s: []const u8) JsonError!Value {
    var stream = std.io.StreamSource{ .const_buffer = std.io.fixedBufferStream(s) };
    return try parse(allocator, &stream);
}

fn parseImpl(allocator: Allocator, s: *PeekStream) JsonError!Value {
    try skipWhitespace(s);
    const r = s.reader();
    const byte = r.readByte() catch |err| switch (err) {
        error.EndOfStream => return JsonError.SyntaxError,
        else => return err,
    };
    try s.putBackByte(byte);
    const value = switch (byte) {
        '{' => Value{ .Object = try parseObject(allocator, s) },
        '[' => Value{ .Array = try parseArray(allocator, s) },
        '"' => Value{ .String = try parseString(allocator, s) },
        't' => Value{ .Bool = try parseTrue(s) },
        'f' => Value{ .Bool = try parseFalse(s) },
        'n' => Value{ .Null = try parseNull(s) },
        '0'...'9', '-', 'e', '.' => Value{ .Number = try parseNumber(allocator, s) },
        else => JsonError.SyntaxError,
    };
    return value;
}

test "parse empty" {
    const json_str = "";
    var v = parseJsonString(std.testing.allocator, json_str);
    try std.testing.expectError(JsonError.SyntaxError, v);
}

test "parse invalid json" {
    const json_str = "asdf";
    var v = parseJsonString(std.testing.allocator, json_str);
    try std.testing.expectError(JsonError.SyntaxError, v);
}

test "parse null" {
    const json_str = "null";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Null);
}

test "parse false" {
    const json_str = "false";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Bool);
    try std.testing.expect(v.Bool == false);
}

test "parse true" {
    const json_str = "true";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Bool);
    try std.testing.expect(v.Bool == true);
}

test "parse number" {
    const json_str = "123.456";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Number);
    try std.testing.expect(v.Number == 123.456);
}

test "parse invalid number" {
    const json_str = "123.456asdf";
    var v = parseJsonString(std.testing.allocator, json_str);
    try std.testing.expectError(JsonError.SyntaxError, v);
}

test "parse empty string" {
    const json_str =
        \\""
    ;
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .String);
    try std.testing.expect(v.String.items.len == 0);
}

test "parse string" {
    const json_str = "123.456";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Number);
    try std.testing.expect(v.Number == 123.456);
}

test "parse empty array" {
    const json_str = "[]";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Array);
    try std.testing.expect(v.Array.items.len == 0);
}

test "parse complex array" {
    const json_str =
        \\[
        \\    "test",
        \\    20,
        \\    ["programming", "gaming", "reading"],
        \\    true,
        \\    false,
        \\    null,
        \\    {
        \\        "key": "value"
        \\    }
        \\]
    ;
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Array);
    const items = v.Array.items;
    try std.testing.expect(items.len == 7);
    try std.testing.expectEqualSlices(u8, items[0].String.items, "test");
    try std.testing.expect(items[1].Number == 20);
    try std.testing.expect(items[2] == .Array);
    const inner = items[2].Array;
    try std.testing.expect(inner.items.len == 3);
    try std.testing.expectEqualSlices(u8, inner.items[0].String.items, "programming");
    try std.testing.expectEqualSlices(u8, inner.items[1].String.items, "gaming");
    try std.testing.expectEqualSlices(u8, inner.items[2].String.items, "reading");
    try std.testing.expect(items[3] == .Bool);
    try std.testing.expect(items[3].Bool);
    try std.testing.expect(items[4] == .Bool);
    try std.testing.expect(items[4].Bool == false);
    try std.testing.expect(items[5] == .Null);
    try std.testing.expect(items[6] == .Object);
    const object = items[6].Object;
    try std.testing.expect(object.count() == 1);
    try std.testing.expect(object.get("key") != null);
    try std.testing.expectEqualSlices(u8, object.get("key").?.String.items, "value");
}

test "parse empty object" {
    const json_str = "{}";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Object);
    try std.testing.expect(v.Object.count() == 0);
}

test "parse complex object" {
    const json_str =
        \\{
        \\    "name": "test",
        \\    "age": 20,
        \\    "hobbies": ["programming", "gaming", "reading"],
        \\    "isMale": true,
        \\    "isFemale": false,
        \\    "null": null,
        \\    "object": {
        \\        "key": "value"
        \\    }
        \\}
    ;
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Object);
    const json = v.Object;
    try std.testing.expectEqualSlices(u8, json.get("name").?.String.items, "test");
    try std.testing.expect(json.get("hobbies").? == .Array);
    const items = json.get("hobbies").?.Array.items;
    try std.testing.expect(items.len == 3);
    try std.testing.expectEqualSlices(u8, items[0].String.items, "programming");
    try std.testing.expectEqualSlices(u8, items[1].String.items, "gaming");
    try std.testing.expectEqualSlices(u8, items[2].String.items, "reading");
    try std.testing.expect(json.get("isMale").? == .Bool);
    try std.testing.expect(json.get("isMale").?.Bool);
    try std.testing.expect(json.get("isFemale").? == .Bool);
    try std.testing.expect(json.get("isFemale").?.Bool == false);
    try std.testing.expect(json.get("null").? == .Null);
    try std.testing.expect(json.get("object").? == .Object);
    const object = json.get("object").?.Object;
    try std.testing.expect(object.count() == 1);
    try std.testing.expect(object.get("key") != null);
    try std.testing.expectEqualSlices(u8, object.get("key").?.String.items, "value");
}
