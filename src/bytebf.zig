const bf = @import("./bf.zig");
const std = @import("std");

const File = std.fs.File;

// The bytecode uses these instructions, then some data specific to the
// instruction.
const BInst = enum (u8) {
    Plus,    // {Plus, val: u8}
    Minus,   // {Minus, val: u8}
    Left,    // {Left, val: u16 (high, low)}
    Right,   // {Right, val: u16 (high, low)}
    LBracket,// {LBracket, opposite: u16 (high, low)}
    RBracket,// {RBracket, opposite: u16 (high, low)}
    WriteOne,// {Write, val: u32}
    WriteRep,// {Write}
    Read,    // {Read}
};

pub fn to_bytecode(program: []const bf.Inst, alloc: std.mem.Allocator) !std.ArrayList(u8) {
    var ret = std.ArrayList(u8).init(alloc);
    errdefer ret.deinit();
    for (program) |inst| {
        switch (inst) {
            .Plus => |n| {
                try ret.append(@enumToInt(BInst.Plus));
                // adding anything larget than 255 will wrap, so n can get
                // cast to a u8.
                const val = @intCast(u8, n);
                try ret.append(val);
            },
            .Minus => |n| {
                try ret.append(@enumToInt(BInst.Minus));
                const val = @intCast(u8, n);
                try ret.append(val);
            },
            .Left => |n| {
                try ret.append(@enumToInt(BInst.Left));
                const val = @intCast(u16, n);
                const low = @intCast(u8, val & 0xFF);
                const high = @intCast(u8, (val >> 8) & 0xFF);
                try ret.append(high);
                try ret.append(low);
            },
            .Right => |n| {
                try ret.append(@enumToInt(BInst.Right));
                const val = @intCast(u16, n);
                const low = @intCast(u8, val & 0xFF);
                const high = @intCast(u8, (val >> 8) & 0xFF);
                try ret.append(high);
                try ret.append(low);
            },
            .Read => {
                try ret.append(@enumToInt(BInst.Read));
            },
            .Write => |n| {
                if (n == 1) {
                    try ret.append(@enumToInt(BInst.WriteOne));
                } else {
                    try ret.append(@enumToInt(BInst.WriteRep));
                    const val = @intCast(u32, n);
                    // val needs to be split into bytes
                    const low  = @intCast(u8, val & 0xFF);
                    const b2   = @intCast(u8, (val >> 8) & 0xFF);
                    const b3   = @intCast(u8, (val >> 16) & 0xFF);
                    const high = @intCast(u8, (val >> 24) & 0xFF);
                    try ret.append(high);
                    try ret.append(b3);
                    try ret.append(b2);
                    try ret.append(low);
                }
            },
            .LBracket => |end| {
                try ret.append(@enumToInt(BInst.LBracket));
                const val = @intCast(u16, end orelse return bf.FindErr.Unmatched);
                const low = @intCast(u8, val & 0xFF);
                const high = @intCast(u8, (val >> 8) & 0xFF);
                try ret.append(high);
                try ret.append(low);
            },
            .RBracket => |start| {
                try ret.append(@enumToInt(BInst.RBracket));
                const val = @intCast(u16, start);
                const low = @intCast(u8, val & 0xFF);
                const high = @intCast(u8, (val >> 8) & 0xFF);
                try ret.append(high);
                try ret.append(low);
            }
        }
    }
    return ret;
}

const InterpErr = error {
    InvalidInstruction,
};

pub fn interpret_bytecode(code: []const u8, in: File, out: File) !void {
    var tape: [bf.tape_len]u8 = .{0} ** bf.tape_len;
    var ptr: usize = 0;
    var iptr: usize = 0;
    const inr = in.reader();
    while (iptr < code.len) {
        switch (code[iptr]) {
            // For each of these we need to:
            //  * extract the necessary data from the bytecode (ie val)
            //  * perform the operation
            //  * increment iptr the right amount to land on the next
            //    instruction- not on the garbage value data which is after
            //    the instruction in the bytecode.
            @enumToInt(BInst.Plus) => {
                const val = code[iptr + 1];
                tape[ptr] +%= val;
                iptr += 2; // skip over val byte
            },
            @enumToInt(BInst.Minus) => {
                // same as plus but subtract.
                const val = code[iptr + 1];
                tape[ptr] -%= val;
                iptr += 2;
            },
            @enumToInt(BInst.Left) => {
                // reassemble u16
                const high = code[iptr + 1];
                const low = code[iptr + 2];
                const val: u16 = (@intCast(u16, high) << 8) | low;
                // move ptr left by subtracting
                std.debug.print("subbing {x} (ptr {} iptr {})\n", .{val, ptr, iptr});
                ptr -= val;
                iptr += 3; // skip over both value bytes.
            },
            @enumToInt(BInst.Right) => {
                // same as left but add instead of subtracting
                const high = code[iptr + 1];
                const low = code[iptr + 2];
                const val: u16 = (@intCast(u16, high) << 8) | low;
                ptr += val; // move right by adding
                iptr += 3; // skip over both value bytes.
            },
            @enumToInt(BInst.WriteOne) => {
                // this is basically the same as in the other interpreter.
                const val = tape[ptr];
                const i_s: *const [1]u8 = &val;
                _ = try out.write(i_s);
                iptr += 1; // no value to skip over, just the instruction.
            },
            @enumToInt(BInst.WriteRep) => {
                // reassemble u32
                const high = code[iptr + 1];
                const b2   = code[iptr + 2];
                const b1   = code[iptr + 3];
                const low  = code[iptr + 4];
                const n = (
                    (@intCast(u32, high) << 24) |
                    (@intCast(u32, b2) << 16) |
                    (@intCast(u32, b1) << 8) |
                    low
                );

                const char = tape[ptr];
                var i: usize = 0;
                const i_s: *const [1]u8 = &char;
                while (i < n) : (i += 1) {
                    _ = try out.write(i_s);
                }
                iptr += 5;
            },
            @enumToInt(BInst.Read) => {
                tape[ptr] = try inr.readByte();
                iptr += 1;
            },
            @enumToInt(BInst.LBracket) => {
                // if this tape cell is 0, jump. Otherwise, skip over this
                // instruction and its end address bytes.
                if (tape[ptr] == 0) {
                    // reassemble u16 of end address.
                    // this is pretty similar to left and right
                    const high = code[iptr + 1];
                    const low = code[iptr + 2];
                    const opposite: u16 = (@intCast(u16, high) << 8) | low;
                    // jump!
                    iptr = opposite + 3;
                } else iptr += 3; // skip over both value bytes.
            },
            @enumToInt(BInst.RBracket) => {
                // basically same as lbracket
                if (tape[ptr] != 0) {
                    const high = code[iptr + 1];
                    const low = code[iptr + 2];
                    const opposite: u16 = (@intCast(u16, high) << 8) | low;
                    iptr = opposite + 3;
                } else iptr += 3; // skip over both value bytes.
            },
            else => {
                //invalid instruction!
                std.log.err("Invalid instruction at iptr {}! next 5: {} {} {} {} {}",
                    .{
                        iptr,
                        code[iptr],
                        code[iptr + 1],
                        code[iptr + 2],
                        code[iptr + 3],
                        code[iptr + 4],
                    }
                );
                return InterpErr.InvalidInstruction;
            }
        }
    }
}

pub fn disassemble_bytecode(code: []const u8) InterpErr!void {
    var iptr: usize = 0;
    while (iptr < code.len) {
        switch (code[iptr]) {
            @enumToInt(BInst.Plus) => {
                const val = code[iptr + 1];
                std.debug.print("{:0>6} Plus {}\n", .{iptr, val});
                iptr += 2; // skip over val byte
            },
            @enumToInt(BInst.Minus) => {
                // same as plus but subtract.
                const val = code[iptr + 1];
                std.debug.print("{:0>6} Minus {}\n", .{iptr, val});
                iptr += 2;
            },
            @enumToInt(BInst.Left) => {
                // reassemble u16
                const high = code[iptr + 1];
                const low = code[iptr + 2];
                const val: u16 = (@intCast(u16, high) << 8) | low;
                std.debug.print("{:0>6} Left {x} {x} ({})\n", .{iptr, high, low, val});
                iptr += 3; // skip over both value bytes.
            },
            @enumToInt(BInst.Right) => {
                // same as left but add instead of subtracting
                const high = code[iptr + 1];
                const low = code[iptr + 2];
                const val: u16 = (@intCast(u16, high) << 8) | low;
                std.debug.print("{:0>6} Left {x} {x} ({})\n", .{iptr, high, low, val});
                iptr += 3; // skip over both value bytes.
            },
            @enumToInt(BInst.WriteOne) => {
                // this is basically the same as in the other interpreter.
                std.debug.print("{:0>6} WriteOne\n", .{iptr});
                iptr += 1; // no value to skip over, just the instruction.
            },
            @enumToInt(BInst.WriteRep) => {
                // reassemble u32
                const high = code[iptr + 1];
                const b2   = code[iptr + 2];
                const b1   = code[iptr + 3];
                const low  = code[iptr + 4];
                const n = (
                    (@intCast(u32, high) << 24) |
                    (@intCast(u32, b2) << 16) |
                    (@intCast(u32, b1) << 8) |
                    low
                );
                
                std.debug.print("{:0>6} WriteRep {x} {x} {x} {x} ({})\n", .{iptr, high, b2, b1, low, n});

                iptr += 5;
            },
            @enumToInt(BInst.Read) => {
                std.debug.print("{:0>6} Read\n", .{iptr});
                iptr += 1;
            },
            @enumToInt(BInst.LBracket) => {
                    const high = code[iptr + 1];
                    const low = code[iptr + 2];
                    const opposite: u16 = (@intCast(u16, high) << 8) | low;
                    std.debug.print("{:0>6} LBracket {} {} ({})\n", .{iptr, high, low, opposite});
                    iptr += 3; // skip over both value bytes.
            },
            @enumToInt(BInst.RBracket) => {
                    const high = code[iptr + 1];
                    const low = code[iptr + 2];
                    const opposite: u16 = (@intCast(u16, high) << 8) | low;
                    std.debug.print("{:0>6} RBracket {} {} ({})\n", .{iptr, high, low, opposite});
                    iptr += 3; // skip over both value bytes.
            },
            else => {
                //invalid instruction!
                std.log.err("Invalid instruction! next 5: {} {} {} {} {}",
                    .{
                        code[iptr],
                        code[iptr + 1],
                        code[iptr + 2],
                        code[iptr + 3],
                        code[iptr + 4],
                    }
                );
                return InterpErr.InvalidInstruction;
            }
        }
    }
}