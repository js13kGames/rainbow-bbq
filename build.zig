const std = @import("std");

const dir: std.Build.InstallDir = std.Build.InstallDir.prefix;
const named_dir: std.Build.InstallDir = .{ .custom = "named" };

pub fn build(b: *std.Build) void {
    // First things first, build assets
    const asset_builder = b.addExecutable(.{
        .name = "asset_builder",
        .root_module = b.addModule("asset_builder", .{
            .root_source_file = b.path("src/build/texture_builder.zig"),
            .target = b.graph.host,
            // .optimize = .safe,
        }),
    });

    const texture_dir = b.path("assets/sprites");

    // Ok, and now actually compile assets
    const compile_assets_step = b.addRunArtifact(asset_builder);
    compile_assets_step.has_side_effects = true;
    compile_assets_step.addDirectoryArg(texture_dir);
    const atlas_bin = compile_assets_step.addOutputFileArg("atlas.bin");
    const sprite_zig = compile_assets_step.addOutputFileArg("Sprite.zig");
    compile_assets_step.step.dependOn(watchDirectory(b, texture_dir));

    const target_wasm = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
        .cpu_features_add = std.Target.wasm.featureSet(&.{
            .nontrapping_fptoint,
            .simd128,
            .bulk_memory,
            .multivalue,
            .sign_ext,
        }),
    });

    const optimize = b.standardOptimizeOption(.{});

    // Build game executable
    const game_exe = b.addExecutable(.{
        .name = "game",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target_wasm,
            .optimize = optimize,
        }),
    });
    game_exe.rdynamic = true;
    game_exe.entry = .disabled;
    game_exe.import_memory = true;

    game_exe.root_module.addAnonymousImport("Sprite", .{
        .root_source_file = sprite_zig,
    });
    game_exe.root_module.addAnonymousImport("atlas.bin", .{
        .root_source_file = atlas_bin,
    });

    const install_step = b.getInstallStep();
    const wat_step = b.step("wat", "convert stuff to .wat");
    const zip_step = b.step("zip", "package everything to a .zip");

    // Initialize packaging process
    const package_exe = b.addExecutable(.{
        .name = "package_zip",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/build/package.zig"),
            .target = b.resolveTargetQuery(.{}),
        }),
    });

    // Start building arguments
    const package_run = b.addRunArtifact(package_exe);
    package_run.color = .enable;
    package_run.has_side_effects = true;
    const game_zip = package_run.addOutputFileArg("game.zip");

    const install_zip = b.addInstallFileWithDir(game_zip, dir, "game.zip");
    install_zip.step.dependOn(&package_run.step);
    zip_step.dependOn(&install_zip.step);

    // Install un-minified game binary
    install_step.dependOn(&b.addInstallArtifact(game_exe, .{
        .dest_dir = .{ .override = named_dir },
    }).step);

    const watanize_main_step = watanize(b, game_exe, "game.wat");
    wat_step.dependOn(watanize_main_step);

    // Minify game WASM module
    {
        const minify_exe = b.addExecutable(.{
            .name = "minify_wasm",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/build/wasm_minify.zig"),
                .target = b.graph.host,
                // .optimize = .safe,
            }),
        });

        // Minify this thing
        const minify_step = b.addRunArtifact(minify_exe);
        minify_step.addArtifactArg(game_exe);
        const minified_exe = minify_step.addOutputFileArg("game.min.wasm");

        // Install minified file
        const install_minified = b.addInstallFileWithDir(minified_exe, dir, "0");
        install_step.dependOn(&install_minified.step);

        // Install (named) minified file
        const install_named = b.addInstallFileWithDir(minified_exe, named_dir, "game.min.wasm");
        install_step.dependOn(&install_named.step);

        // Turn minified file to WAT
        const watanize_min_step = watanize(b, minified_exe, "game.min.wat");
        wat_step.dependOn(watanize_min_step);

        // Add minified WASM to .zip
        package_run.step.dependOn(&minify_step.step);
        package_run.step.dependOn(&install_minified.step);
        package_run.addArg("zig-out/0");
    }

    // Install frontend web things
    const static_dir = b.path("static");
    switch (optimize) {
        .Debug => {
            const dir_step = b.addInstallDirectory(.{
                .source_dir = static_dir,
                .install_dir = dir,
                .install_subdir = "",
            });

            install_step.dependOn(&dir_step.step);
            package_run.step.dependOn(&dir_step.step);
            package_run.addDirectoryArg(static_dir);
        },
        else => {
            const minify_exe = b.addExecutable(.{
                .name = "minify_html",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/build/html_minify.zig"),
                    .target = b.graph.host,
                    // .optimize = .safe,
                }),
            });

            // Run minifier
            const minify_step = b.addRunArtifact(minify_exe);
            minify_step.has_side_effects = true;
            minify_step.addDirectoryArg(static_dir);
            const minified_html = minify_step.addOutputFileArg("index.min.html");
            minify_step.addArg("index.html");
            minify_step.step.dependOn(watchDirectory(b, static_dir));

            // Install minified file as index.html
            const install_minified = b.addInstallFileWithDir(minified_html, dir, "index.html");
            install_step.dependOn(&install_minified.step);

            // Add minified HTML to the .zip
            package_run.step.dependOn(&install_minified.step);
            package_run.step.dependOn(watchDirectory(b, static_dir));
            package_run.addArg("zig-out/index.html");
        },
    }
}

fn dumpTree(b: *std.Build, step: *std.Build.Step, w: *std.Io.Writer, depth: usize) !void {
    for (0..depth) |_| {
        try w.writeAll("  ");
    }

    try w.print("'{s}' ({}): ", .{ step.name, step.tag });
    if (step.dependencies.items.len == 0) {
        try w.writeAll("[]\n");
        return;
    }

    try w.writeAll("[\n");
    for (step.dependencies.items) |dep| {
        try dumpTree(b, dep, w, depth + 1);
    }

    for (0..depth) |_| {
        try w.writeAll("  ");
    }
    try w.writeAll("]\n");
}

// Translate WASM to WAT, because it would be really funny
fn watanize(b: *std.Build, file: anytype, wat_fname: []const u8) *std.Build.Step {
    const wat_step = b.addSystemCommand(&.{"wasm2wat"});

    switch (@TypeOf(file)) {
        *std.Build.Step.Compile => wat_step.addArtifactArg(file),
        std.Build.LazyPath => wat_step.addFileArg(file),
        else => unreachable,
    }

    wat_step.addArg("-o");
    const wat_out = wat_step.addOutputFileArg(".wat");

    const install_wat_step = b.addInstallFileWithDir(wat_out, named_dir, wat_fname);

    return &install_wat_step.step;
}

fn watchDirectory(b: *std.Build, dir_path: std.Build.LazyPath) *std.Build.Step {
    return &b.addInstallDirectory(.{
        .install_dir = .{ .custom = "" },
        .install_subdir = "",
        .source_dir = dir_path,
        .include_extensions = &.{},
    }).step;
}
