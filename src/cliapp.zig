const std = @import("std");
const Allocator = std.mem.Allocator;

// FIXME: can't we not use the Zig types?? It feels so weird
// having this enum...
pub const ArgType = enum {
    t_u8,
    t_u32,
    t_str,
};

pub const Argument = struct {
    const Self = @This();

    target: []const u8,
    flags: []const []const u8,
    typ: ArgType,
    optional: bool = false,
    help: ?[]const u8 = null,

    default_u8: ?u8 = null,
    default_u32: ?u32 = null,
    default_str: ?[]const u8 = null,

    value_u8: ?u8 = null,
    value_u32: ?u32 = null,
    value_str: ?[]const u8 = null,


    fn parse_value(self: *Self, value: []const u8) !void {
        switch (self.typ) {
            ArgType.t_str => self.value_str = value,
            ArgType.t_u8 => {
                self.value_u8 = std.fmt.parseInt(u8, value, 10) catch |e| {
                    std.debug.print("Could not parse u8 int from {s}: {any}\n", .{ value, e });
                    return error.ParseValue;
                };
            },
            ArgType.t_u32 => {
                self.value_u32 = std.fmt.parseInt(u32, value, 10) catch |e| {
                    std.debug.print("Could not parse u32 int from {s}: {any}\n", .{ value, e });
                    return error.ParseValue;
                };
            },
        }
    }
};

pub const ArgParser = struct {
    const Self = @This();

    program: []const u8,
    description: ?[]const u8 = null,
    arg_help: Argument = .{
        .target = "help",
        .flags = &.{ "-h", "--help" },
        .typ = ArgType.t_str,
        .help = "Show this help"
    },

    // Below are not to be accessed
    allocator: Allocator,

    // HashMap mapping target to Argument
    args: std.StringHashMapUnmanaged(Argument) = std.StringHashMapUnmanaged(Argument).empty,
    // HashMap mapping flags to their target
    targets: std.StringHashMapUnmanaged([]const u8) = std.StringHashMapUnmanaged([]const u8).empty,
    commands_padding: u8 = 0,

    pub fn init(alloc: Allocator, program: []const u8, description: ?[]const u8) Self {
        return .{
            .program = program,
            .description = description,
            .arg_help = .{
                .target = "help",
                .flags = &.{ "-h", "--help" },
                .typ = ArgType.t_str,
                .help = "Show this help"
            },
            .allocator = alloc,
            .args = std.StringHashMapUnmanaged(Argument).empty,
            .targets = std.StringHashMapUnmanaged([]const u8).empty,
            .commands_padding = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.targets.deinit(self.allocator);
        self.args.deinit(self.allocator);
    }

    /// Parse command line arguments based on arguments added.
    pub fn parse_args(self: *Self) !void {
        var arg_it = try std.process.argsWithAllocator(self.allocator);
        defer arg_it.deinit();

        _ = arg_it.next();  // skip progam arg

        // Parse values from input into their Argument
        while (arg_it.next()) |flag| {
            const target = self.targets.get(flag);
            if (target != null) {
                const value = arg_it.next();  // get arg value
                if (value != null) {
                    var argument = self.args.getPtr(target.?) orelse return error.ArgumentDoesNotExist;
                    try argument.parse_value(value.?);
                } else {
                    std.debug.print("Error - No value provided for flag {s}\n", .{ flag });
                    return error.NoValueProvided;
                }
            } else {
                std.debug.print("Warning - Unrecognized flag {s}\n", .{ flag });
            }
        }

        // For Arguments withouth a value parsed, used the default. If default
        // is missing and arg is mandatory, then error
        var args_it = self.args.iterator();
        while (args_it.next()) |entry| {
            var arg = entry.value_ptr;
            switch (arg.typ) {
                ArgType.t_u8 => {
                    if (arg.value_u8 == null) {
                        if (arg.default_u8 == null) {
                            if (!arg.optional)
                                return error.MissingArgumentValue;
                        } else {
                            arg.value_u8 = arg.default_u8;
                        }
                    }
                },
                ArgType.t_u32 => {
                    if (arg.value_u32 == null) {
                        if (arg.default_u32 == null) {
                            if (!arg.optional)
                                return error.MissingArgumentValue;
                        } else {
                            arg.value_u32 = arg.default_u32;
                        }
                    }
                },
                ArgType.t_str => {
                    if (arg.value_str == null) {
                        if (arg.default_str == null) {
                            if (!arg.optional)
                                return error.MissingArgumentValue;
                        } else {
                            arg.value_str = arg.default_str;
                        }
                    }
                },
            }
        }
    }

    /// Add a new argument to the ArgParser.
    pub fn add_argument(self: *Self, arg: Argument) !void {
        // Populate args, targets
        try self.args.put(self.allocator, arg.target, arg);
        for (arg.flags) |flag|
            try self.targets.put(self.allocator, flag, arg.target);

        // Update padding so later we can use it to properly
        // align descriptions when we show the help
        var arg_padding: u8 = 0;
        for (arg.flags, 0..) |flag, i|
            arg_padding += @as(u8, @intCast(flag.len)) + @as(u8, if (i > 0) 2 else 0);

        if (arg_padding > self.commands_padding)
            self.commands_padding = arg_padding;
    }

    /// Get Argument for provided target
    pub fn get(self: Self, target: []const u8) !Argument {
        return self.args.get(target) orelse error.TargetDoesNotExist;
    }

    /// Show help
    pub fn show_help(self: *Self) void {
        // show usage
        std.debug.print("usage: {s} ", .{self.program});

        for (self.arg_help.flags, 0..) |flag, i| {
            std.debug.print("{s}{s} {s}", .{if (i == 0) "[ " else "| ", flag, if (i == self.arg_help.flags.len - 1) "] " else ""});
        }

        var arg_it = self.args.valueIterator();
        while (arg_it.next()) |arg| {
            if (arg.flags.len > 0) {
                std.debug.print("{s} ", .{ if(arg.optional) "[" else "<" });
                for (arg.flags, 0..) |flag, i| {
                    std.debug.print("{s}{s} ", .{if (i > 0) "| " else "", flag});
                }
                std.debug.print("{s} ", .{ if(arg.optional) "]" else ">" });
            }
        }
        std.debug.print("\n", .{});

        // show description
        if (self.description != null) std.debug.print("\n{s}\n\n", .{self.description.?});

        // show mandatories
        var n_trailing_ws: u8 = self.commands_padding;
        arg_it = self.args.valueIterator();
        if (self.args.count() > 0) std.debug.print("mandatory:\n", .{});
        while (arg_it.next()) |arg| {
            if (!arg.optional and arg.flags.len > 0) {
                n_trailing_ws = self.commands_padding;
                for (arg.flags, 0..) |flag, i| {
                    std.debug.print("{s}{s}", .{if (i > 0) ", " else "  ", flag});
                    n_trailing_ws -= @as(u8, @intCast(flag.len)) + @as(u8, if (i > 0) 2 else 0);
                }

                for (0..n_trailing_ws) |_|
                    std.debug.print(" ", .{});

                std.debug.print("    {s}\n", .{arg.help orelse ""});
            }
        }
        std.debug.print("\n", .{});

        // show optionals
        arg_it = self.args.valueIterator();
        if (self.args.count() > 0) std.debug.print("options:\n", .{});
        while (arg_it.next()) |arg| {
            if (arg.optional and arg.flags.len > 0) {
                n_trailing_ws = self.commands_padding;
                for (arg.flags, 0..) |flag, i| {
                    std.debug.print("{s}{s}", .{if (i > 0) ", " else "  ", flag});
                    n_trailing_ws -= @as(u8, @intCast(flag.len)) + @as(u8, if (i > 0) 2 else 0);
                }

                for (0..n_trailing_ws) |_|
                    std.debug.print(" ", .{});

                std.debug.print("    {s}\n", .{arg.help orelse ""});
            }
        }
        std.debug.print("\n", .{});
    }
};
