const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const cwd = std.Io.Dir.cwd();
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const zip_fname = args[1];
    const input_files = args[2..];

    // Get list of input files
    var input_fnames = try std.ArrayList([]const u8).initCapacity(arena, 16);
    for (input_files) |fname| {
        const fstat = try cwd.statFile(init.io, fname, .{});
        switch (fstat.kind) {
            .file => {
                try input_fnames.append(arena, fname);
            },
            .directory => {
                const dir = try cwd.openDir(init.io, fname, .{ .iterate = true });
                var dir_iter = dir.iterate();
                while (try dir_iter.next(init.io)) |dir_file| {
                    const dfile_path = try std.Io.Dir.path.join(arena, &.{ fname, dir_file.name });
                    try input_fnames.append(arena, dfile_path);
                }
            },
            else => @panic("whar"),
        }
    }

    // Run ZIP
    const result = try std.process.run(arena, init.io, .{
        .argv = try std.mem.concat(arena, []const u8, &.{
            &.{ "zip", "-9", "-j", zip_fname },
            input_fnames.items,
        }),
    });
    if (!result.term.success()) {
        std.debug.panic("mama mia :(", .{});
    }

    // Open ZIP file
    const zip_file = try cwd.openFile(init.io, zip_fname, .{});
    defer zip_file.close(init.io);
    const zip_stat = try zip_file.stat(init.io);
    std.log.info("final zip file: {d} bytes", .{zip_stat.size});

    // Print asset sizes
    var zip_buf: [1024]u8 = undefined;
    var zip_r = zip_file.reader(init.io, &zip_buf);
    var zip_iter = try std.zip.Iterator.init(&zip_r);

    while (try zip_iter.next()) |entry| {
        var fname_buf: [512]u8 = undefined;
        const fname = try entry.getFilename(&zip_r, &fname_buf, .{});
        std.log.info("{s}: {d} bytes ({d} zipped)", .{ fname, entry.uncompressed_size, entry.compressed_size });
    }
}
