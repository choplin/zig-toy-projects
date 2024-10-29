const std = @import("std");
const testing = std.testing;

const allocator = std.heap.page_allocator;

const Node = struct {
    object: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        compute: *const fn (self: *Node) i32,
    };

    pub fn compute(self: *Node) i32 {
        return self.vtable.compute(self);
    }

    pub fn make(object: anytype) Node {
        const ObjectPtrType = @TypeOf(@constCast(object));
        return Node{
            .object = @constCast(object),
            .vtable = &VTable{
                .compute = struct {
                    fn compute(self: *Node) i32 {
                        const TypedObject: ObjectPtrType = @ptrCast(@alignCast(self.object));
                        return TypedObject.compute();
                    }
                }.compute,
            },
        };
    }
};

const LiteralValue = struct {
    value: i32,
    pub fn compute(self: *LiteralValue) i32 {
        return self.value;
    }
};

const Square = struct {
    input: *Node,
    pub fn compute(self: *Square) i32 {
        const val = self.input.compute();
        return val * val;
    }
};

const Plus = struct {
    left: *Node,
    right: *Node,
    pub fn compute(self: *Plus) i32 {
        return self.left.compute() + self.right.compute();
    }
};

const Multiply = struct {
    left: *Node,
    right: *Node,
    pub fn compute(self: *Multiply) i32 {
        return self.left.compute() * self.right.compute();
    }
};

test "literal comptues expected value" {
    var node = Node.make(&LiteralValue{ .value = 3 });
    try testing.expectEqual(@as(i32, 3), node.compute());
}

test "square computes expected value" {
    var three_node = Node.make(&LiteralValue{ .value = 3 });
    var four_node = Node.make(&LiteralValue{ .value = 4 });
    var plus = Plus{ .left = &three_node, .right = &four_node };
    try testing.expectEqual(@as(i32, 7), plus.compute());
}

test "(2+3)*(4*5) == 100" {
    var two = Node.make(&LiteralValue{ .value = 2 });
    var three = Node.make(&LiteralValue{ .value = 3 });
    var four = Node.make(&LiteralValue{ .value = 4 });
    var five = Node.make(&LiteralValue{ .value = 5 });

    var left = Node.make(&Plus{
        .left = &two,
        .right = &three,
    });
    var right = Node.make(&Multiply{
        .left = &four,
        .right = &five,
    });
    var expr = Node.make(&Multiply{
        .left = &left,
        .right = &right,
    });
    try testing.expectEqual(@as(i32, 100), expr.compute());
}
