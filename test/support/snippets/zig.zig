const ParseError = error{ Empty, TooLong };
fn parse(text: []const u8) ParseError!u32 {
    if (text.len == 0) return error.Empty;
    errdefer cleanup();
    const n = std.fmt.parseInt(u32, text, 10) catch |err| return err;
    const v: ?u32 = null;
    _ = try other(true);
    return v orelse unreachable;
}
