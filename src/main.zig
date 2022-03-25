const std = @import("std");
const bf = @import("./bf.zig");

const alloc = std.heap.page_allocator;

pub fn main() anyerror!void {
    // std.log.info("All your codebase are belong to us.", .{});
    var args = std.process.args();
    var arglist = std.ArrayList([]const u8).init(alloc); defer arglist.deinit();

    while (args.next(alloc)) |arg| {
        try arglist.append(try arg);
    }
    defer for (arglist.items) |arg| {
        alloc.free(arg);
    };

    const stdout = std.io.getStdOut().writer();

    // for (arglist.items) |arg, i| {
    //     std.debug.print("{}: {s}\n", .{i, arg});
    // }
    // std.debug.print("{}\n", .{arglist.items.len});
    if (arglist.items.len != 2) {
        // there should always be at least one element, which is this program
        try stdout.print("usage: {s} [path_to_file.bf]\n", .{arglist.items[0]});
        return;
    }

    const filename = arglist.items[1];
    const src_file = try std.fs.cwd().openFile(filename, std.fs.File.OpenFlags {
        .read = true,
    });

    var bytes = try alloc.alloc(u8, try src_file.getEndPos());
    defer alloc.free(bytes);

    _ = try src_file.readAll(bytes);

    _ = try stdout.write(bytes);
}

test "basic test" {
    try std.testing.expectEqual(10, 3 + 7);
}
