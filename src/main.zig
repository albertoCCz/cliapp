const std = @import("std");

const cliapp = @import("./cliapp.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    const alloc = gpa.allocator();

    var arg_parser = cliapp.ArgParser.init(
        alloc,
        "awesome_program",
        "We do a bunch of interesting stuff!",
    );
    defer arg_parser.deinit();

    // Add the arguments to the arg parser
    try arg_parser.add_argument(.{
        .target = "time",
        .flags = &.{ "-t", "--time" },
        .typ = cliapp.ArgType.t_u8,
        .optional = true,
        .help = "Time it takes to do something awesome",
        // .default_u8 = 12,
    });
    try arg_parser.add_argument(.{
        .target = "name",
        .flags = &.{ "-n", "--namesuperlongtestalingment" },
        .typ = cliapp.ArgType.t_str,
        .optional = true,
        .help = "Name of lsomething!",
        .default_str = "Default string"
    });
    try arg_parser.add_argument(.{
        .target = "string",
        .flags = &.{ "-s" },
        .typ = cliapp.ArgType.t_str,
        .help = "Some help for this argument",
        // .default_str = "Another default string"
    });

    arg_parser.show_help();
    try arg_parser.parse_args();

    const arg_name = try arg_parser.get("name");
    std.debug.print("arg_name: {?s}\n", .{ arg_name.value_str });

    const arg_s = try arg_parser.get("string");
    std.debug.print("arg_s: {?s}\n", .{ arg_s.value_str });
}
