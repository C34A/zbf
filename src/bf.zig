const std = @import("std");

// -------------------- parse --------------------

pub const Inst = union (enum) {
    Plus: usize, // count
    Minus: usize, // count
    Left: usize, // count
    Right: usize, // count
    LBracket: ?usize, // end index. null until we set it later. SHOULD NOT BE NULL IN DATA RETURNED FROM PARSE!
    RBracket: usize, // start index
    Write: usize, // count
    Read,
};

pub fn parse(code: []const u8, alloc: std.mem.Allocator) !std.ArrayList(Inst) {
    var ret = std.ArrayList(Inst).init(alloc);
    errdefer ret.deinit(); // if we return an error, make sure to free the arraylist
    var i: usize = 0;
    // Each time we find a bracket, we push its index onto this stack.
    // When we find a close bracket, we pop the top index, set that for this
    // bracket, then go back and find the start bracket using the index and set
    // its end to the current index.
    // "index" in the output instruction list is kept track of by the arraylist
    // len, so we don't need to worry about it.
    var bracket_stack = std.ArrayList(usize).init(alloc);
    defer bracket_stack.deinit();

    while (i < code.len) {
        switch (code[i]) {
            '+' => {
                const count = get_count(code, i);
                i += count;
                try ret.append(Inst{.Plus = count});
            },
            '-' => {
                const count = get_count(code, i);
                i += count;
                try ret.append(Inst{.Minus = count});
            },
            '<' => {
                const count = get_count(code, i);
                i += count;
                try ret.append(Inst{.Left = count});
            },
            '>' => {
                const count = get_count(code, i);
                i += count;
                try ret.append(Inst{.Right = count});
            },
            '[' => {
                try bracket_stack.append(ret.items.len);
                try ret.append(Inst{.LBracket = null});
                i += 1;
            },
            ']' => {
                const open_idx = bracket_stack.popOrNull() orelse return FindErr.Unmatched;
                const close_idx = ret.items.len;
                try ret.append(Inst{.RBracket = open_idx});
                // go back and set the open bracket to point to the new close bracket
                // it is easier to just overwrite it than mutate the existing value
                ret.items[open_idx] = Inst{.LBracket = close_idx};
                i += 1;
            },
            ',' => {
                try ret.append(Inst.Read);
                i += 1;
            },
            '.' => {
                const count = get_count(code, i);
                i += count;
                try ret.append(Inst{.Write = count});
            },
            else => {i += 1;}, // ignore all other characters
        }
    }
    return ret;
}

fn get_count(code: []const u8, start: usize) usize {
    const char = code[start];
    var i = start + 1;
    while (i < code.len and code[i] == char) : (i += 1) {}
    return i - start;
}

// -------------------- exec --------------------

pub const tape_len = 30_000;
const File = std.fs.File;

pub fn interpret(code: []const Inst, in: File, out: File) !void {
    var tape: [tape_len]u8 = .{0} ** tape_len;
    var ptr: usize = 0;
    var iptr: usize = 0;
    const inr = in.reader();
    while (iptr < code.len) : (iptr += 1) {
        switch (code[iptr]) {
            .Plus => |n| {
                tape[ptr] +%= @intCast(u8, n);
            },
            .Minus => |n| {
                tape[ptr] -%= @intCast(u8, n);
            },
            .Left => |n| {
                ptr -= n;
            },
            .Right => |n| {
                ptr += n;
            },
            .Write => |n| {
                const char = tape[ptr];
                var i: usize = 0;
                while (i < n) : (i += 1) {
                    const i_s: *const [1]u8 = &char;
                    _ = try out.write(i_s);
                }
            },
            .Read => {
                tape[ptr] = try inr.readByte();
            },
            .LBracket => |end| {
                if (tape[ptr] == 0) iptr = end.?;
            },
            .RBracket => |start| {
                if (tape[ptr] != 0) iptr = start;
            }
        }
        // std.debug.print("======\ntape {*}\nptr {} iptr {}\ninst {}\n", .{tape[0..20], ptr, iptr, code[iptr]});
    }
}

pub const FindErr = error {
    IllegalStart, // didn't start on bracket
    Unmatched,    // didn't find a match
};

// Find the index of the instruction after the bracket matching
// the one at code[iptr].
// fn find(code: []const Inst, iptr: usize) FindErr!usize {
//     const start = code[iptr];
//     const opposite = switch (start) {
//         .LBracket => Inst.RBracket,
//         .RBracket => Inst.LBracket,
//         else => return FindErr.IllegalStart,
//     };
//     const direction: i8 = switch (start) {
//         .LBracket => 1,
//         .RBracket => -1,
//         else => unreachable,
//     };

//     var depth: usize = 0;
//     var i: i64 = @intCast(i64, iptr) + direction;
//     while (i >= 0 and i < code.len) : (i += direction) {
//         const i_inst = code[@intCast(usize, i)];
//         if (@enumToInt(i_inst) == @enumToInt(opposite)) {
//             if (depth == 0) return @intCast(usize, i);
//             depth -= 1;
//         } else if (@enumToInt(i_inst) == @enumToInt(start)) {
//             depth += 1;
//         }
//     }
//     return FindErr.Unmatched;
// }

// -------------------- tests --------------------

const expect = std.testing.expect;

test "get_count" {
    try expect(3 == get_count("+---[", 1));
    try expect(1 == get_count("+", 0));
    const s = "+---[],.";
    const new_i = get_count(s, 1) + 1;
    try expect(s[new_i] == '[');
}

test "parse" {
    const code = "++---[],.asdf";
    const alloc = std.heap.page_allocator;
    var result = try parse(code[0..], alloc);
    defer result.deinit();

    // try expect(result.items[0] == Inst{.Plus = 2});
    // try expect(result.items[1] == Inst{.Minus = 3});
    // try expect(result.items[2] == Inst.LBracket);
    // try expect(result.items[3] == Inst.RBracket);
    // try expect(result.items[4] == Inst.Read);
    // try expect(result.items[5] == Inst{.Write = 1});
    // todo: find an actual way to test this
    try expect(result.items.len == 6);
}

test "run" {
    const code = "+++++[>++++++++++<-].asdf";
    const alloc = std.heap.page_allocator;
    var result = try parse(code[0..], alloc);
    defer result.deinit();

    // std.debug.print("{}\n", .{result});

    try interpret(result.items, std.io.getStdIn(), std.io.getStdOut());
}