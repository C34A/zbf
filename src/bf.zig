const std = @import("std");

const Inst = union (enum) {
    Plus: usize,
    Minus: usize,
    Left: usize,
    Right: usize,
    LBracket,
    RBracket,
    Write: usize,
    Read,
};


pub fn parse(code: []u8, alloc: std.mem.Allocator) std.ArrayList(Inst) {
    var ret = std.ArrayList(Inst).init(alloc);
    var i: usize = 0;
    while (i < code.len) {
        switch (code[i]) {
            '+' => {
                const count = get_count(code, i);
                i += count;
                ret.append(Inst{.Plus = count});
            },
            '-' => {
                const count = get_count(code, i);
                i += count;
                ret.append(Inst{.Minus = count});
            },
            '<' => {
                const count = get_count(code, i);
                i += count;
                ret.append(Inst{.Left = count});
            },
            '>' => {
                const count = get_count(code, i);
                i += count;
                ret.append(Inst{.Right = count});
            },
            '[' => {
                re.append(Inst{.LBracket});
                i += 1;
            },
            ']' => {
                re.append(Inst{.RBracket});
                i += 1;
            },
            ',' => {
                re.append(Inst{.Read});
                i += 1;
            },
            '.' => {
                const count = get_count(code, i);
                i += count;
                ret.append(Inst{.Write = count});
            },
            _ => {}, // ignore all other characters
        }
    }
    return ret;
}

fn get_count(code: []const u8, start: usize) usize {
    const char = code[start];
    var i = start + 1;
    while (i < code.len and code[i] == char) : (i += 1) {}
    return start - i;
}

const expect = std.testing.expect;

test "get_count" {
    expect(3 == get_count("+---[", 1));
    expect(1 == get_count("+", 0));
    const s = "+---[],.";
    const new_i = get_count(s, 1) + 1;
    expect(s[new_i] == '[');
}

test "parse" {
    const code = "++---[],.asdf";
    const alloc = std.testing.failing_allocator;
    const result = parse(code, alloc);
    defer result.deinit();
}