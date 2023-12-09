# zig-toy-json

A toy implementation of JSON parser to learn Zig language.

## Usage

```zig
test "parse small array" {
    const json_str = "[1,2,3]";
    var v = try parseJsonString(std.testing.allocator, json_str);
    defer v.deinit();
    try std.testing.expect(v == .Array);
    const items = v.Array.items;
    try std.testing.expect(items.len == 3);
    try std.testing.expect(items[0] == .Number);
    try std.testing.expect(items[0].Number == 1);
    try std.testing.expect(items[1] == .Number);
    try std.testing.expect(items[1].Number == 2);
    try std.testing.expect(items[2] == .Number);
    try std.testing.expect(items[2].Number == 3);
}
```

## License

MIT

## Acknowledgements

This project was built upon [mattn/zig-json](https://github.com/mattn/zig-json)
