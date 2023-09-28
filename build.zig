const std = @import("std");

var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
const gpa = gpa_impl.allocator();

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const shared = b.option(bool, "SDL_SHARED", "Build SDL shared library [default: true]") orelse true;

    const lib = if (shared)
        b.addSharedLibrary(.{
            .name = "SDL3-shared",
            .target = target,
            .optimize = optimize,
        })
    else
        b.addStaticLibrary(.{
            .name = "SDL3-static",
            .target = target,
            .optimize = optimize,
        });

    setup(b, lib);
    lib.installHeadersDirectory("include", "");
    b.installArtifact(lib);

    buildTest(b, lib);
}

fn setup(b: *std.Build, lib: *std.Build.Step.Compile) void {
    const t = lib.target_info.target;

    lib.addIncludePath(.{ .path = "include" });
    // lib.addCSourceFiles(&generic_srcs, &.{});
    lib.defineCMacro("SDL_USE_BUILTIN_OPENGL_DEFINITIONS", "1");
    lib.linkLibC();

    var glob_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer glob_arena.deinit();
    const glob_alloc = glob_arena.allocator();

    lib.addCSourceFiles(globSources(glob_alloc, b.build_root.handle, &.{
        "src/*.c",
        "src/atomic/*.c",
        "src/audio/*.c",
        "src/core/*.c",
        "src/cpuinfo/*.c",
        "src/dynapi/*.c",
        "src/events/*.c",
        "src/file/*.c",
        "src/joystick/*.c",
        "src/haptic/*.c",
        "src/hidapi/*.c",
        "src/libm/*.c",
        "src/locale/*.c",
        "src/misc/*.c",
        "src/power/*.c",
        "src/render/*.c",
        "src/render/*/*.c",
        "src/sensor/*.c",
        "src/stdlib/*.c",
        "src/thread/*.c",
        "src/timer/*.c",
        "src/video/*.c",
        "src/video/yuv2rgb/*.c",
    }).items, &.{});

    lib.addIncludePath(.{ .path = "include" });
    lib.addIncludePath(.{ .path = "src" });

    switch (t.os.tag) {
        .windows => {
            // #TODO: All those sections can be enabled or disabled via variables in the cmake version. Do we need that?
            // #TODO: support for windows store is not currently supported
            // #TODO: sensor API is not currently supported
            const windows_srcs = globSources(glob_alloc, b.build_root.handle, &.{
                // Core
                "src/core/windows/*.c",
                // Audio
                "src/audio/directsound/*.c", // #TODO: should we also support wasapi?
                // Video
                "src/video/windows/*c",
                // Threads
                "src/thread/generic/SDL_syscond.c",
                "src/thread/generic/SDL_sysrwlock.c",
                "src/thread/windows/SDL_syscond_cv.c",
                "src/thread/windows/SDL_sysmutex.c",
                "src/thread/windows/SDL_sysrwlock_srw.c",
                "src/thread/windows/SDL_syssem.c",
                "src/thread/windows/SDL_systhread.c",
                "src/thread/windows/SDL_systls.c",
                // Power
                "src/power/windows/SDL_syspower.c",
                // Locale
                "src/locale/windows/*.c",
                // Filesystem
                "src/filesystem/windows/*.c",
                // Timers
                "src/timer/windows/*.c",
                // Loadso
                "src/loadso/windows/*.c",
                // Joystick
                "src/joystick/windows/*.c",
                // Haptic
                "src/haptic/windows/*.c",
            });
            lib.addCSourceFiles(windows_srcs.items, &.{});
            lib.linkSystemLibrary("setupapi");
            lib.linkSystemLibrary("winm");
            lib.linkSystemLibrary("gdi32");
            lib.linkSystemLibrary("imm32");
            lib.linkSystemLibrary("version");
            lib.linkSystemLibrary("oleaut32");
            lib.linkSystemLibrary("ole32");
        },
        .macos => {
            @panic("I do not have a macosx system at hand to test this. Feel free to contribute");
        },
        .linux => {
            const libraries = fetchLinuxSystemLibraries(gpa, b);
            const build_dir = b.build_root.handle;

            const linux_srcs = globSources(glob_alloc, build_dir, &.{
                // Core
                "src/core/unix/*.c",
                "src/core/linux/SDL_evdev_capabilities.c",
                "src/core/linux/SDL_threadprio.c",
                "src/core/linux/SDL_sandbox.c",
                // Audio
                "src/audio/alsa/*.c",
                // Timers
                "src/timer/unix/*.c",
                // Video
                // #TODO: We assume X, vulkan and opengl. This breaks in a number of possible scenarios:
                //  - older system might not support vulkan,
                //  - raspberry pi and other platforms should be checked first and look for GLES
                //  - not broken, but not nice, no wayland.
                // Wayland requires some extra steps because it needs to generate header and sources from the xml
                // protocols.
                "src/video/x11/*.c",
                // Haptics
                "src/haptic/linux/*.c",
                // Joystick
                "src/joystick/linux/*.c",
                "src/joystick/steam/*.c",
                // Threads
                "src/thread/pthread/SDL_systhread.c",
                "src/thread/pthread/SDL_sysmutex.c",
                "src/thread/pthread/SDL_syscond.c",
                "src/thread/pthread/SDL_sysrwlock.c",
                "src/thread/pthread/SDL_systls.c",
                "src/thread/pthread/SDL_syssem.c",
            });
            lib.addCSourceFiles(linux_srcs.items, &.{});

            lib.defineCMacro("_REENTRANT", "1");
            lib.linkSystemLibrary("pthread");
            lib.linkSystemLibrary("m");
            lib.linkSystemLibrary("iconv");

            if (findLinuxLib(gpa, "pipewire-0.3", libraries)) {
                lib.addCSourceFiles(globSources(glob_alloc, build_dir, &.{ "src/audio/pipewire/*.c" }).items, &.{});
                lib.linkSystemLibrary("pipewire-0.3");
            }

            if (findLinuxLib(gpa, "alsa", libraries)) {
                lib.addCSourceFiles(globSources(glob_alloc, build_dir, &.{ "src/audio/alsa/*.c" }).items, &.{});
                lib.linkSystemLibrary("alsa");
            }

            if (findLinuxLib(gpa, "pulse", libraries)) {
                lib.addCSourceFiles(globSources(glob_alloc, build_dir, &.{ "src/audio/pulseaudio/*.c" }).items, &.{});
                lib.linkSystemLibrary("pulse");
            }

        },

        else => {
            @panic("Target not yet implemented");
        },
    }
}

/// Horrible and not very robust glob implementation, but it works for now.
/// Only supports '*' wildcards.
fn globSources(a: std.mem.Allocator, cwd: std.fs.Dir, paths: []const []const u8) std.ArrayList([]const u8) {
    var res = std.ArrayList([]const u8).init(a);

    out: for (paths) |path| {
        var prev_sep: usize = 0;
        for (path, 0..) |c, index| {
            if (c == '/') {
                prev_sep = index;
                continue;
            }

            if (c != '*') {
                continue;
            }

            const next_sep = if (std.mem.indexOfScalar(u8, path[index + 1..], '/')) |pos| pos + index + 1 else path.len;
            const prefix = path[prev_sep + 1..index];
            const postfix = path[index + 1..next_sep];
            const dirpath = path[0..prev_sep];
            // std.log.info("Path: {s}, Prefix: {s}, dirpath: {s}", .{ path, prefix, path[0..prev_sep] });

            var dir = cwd.openIterableDir(dirpath, .{}) catch {
                std.log.err("Failed to find directory: {s}", .{ dirpath });
                unreachable;
            };
            defer dir.close();
            var iter = dir.iterate();

            // If the next separator is the end of the path, we are searching for a file. Otherwise we are iterating
            // over directories.
            if (next_sep == path.len) {
                while (iter.next() catch unreachable) |entry| {
                    if (entry.kind == .file and entry.name.len >= prefix.len + postfix.len and
                        std.mem.startsWith(u8, entry.name, prefix) and std.mem.endsWith(u8, entry.name, postfix))
                    {
                        const newpath = std.fs.path.join(a, &.{
                            dirpath,
                            "/",
                            entry.name,
                        }) catch @panic("OOM");
                        res.append(newpath) catch unreachable;
                    }
                }
                continue :out;
            }

            var subpaths = std.ArrayList([]const u8).init(a);
            defer {
                for (subpaths.items) |sp| { a.free(sp); }
                subpaths.deinit();
            }
            while (iter.next() catch unreachable) |entry| {
                if (entry.kind == .directory and entry.name.len >= prefix.len + postfix.len and
                    std.mem.startsWith(u8, entry.name, prefix) and std.mem.endsWith(u8, entry.name, postfix))
                {
                    const newpath = std.fs.path.join(a, &.{
                        dirpath,
                        "/",
                        entry.name,
                        path[next_sep..],
                    }) catch @panic("OOM");
                    subpaths.append(newpath) catch @panic("OOM");
                }
            }

            if (subpaths.items.len > 0) {
                var subfiles = globSources(a, cwd, subpaths.items);
                defer subfiles.deinit();
                res.appendSlice(subfiles.items) catch @panic("OOM");
            }
            continue :out;
        }

        // If we got here there was no wildcard, so the path better be and actual file
        if (cwd.access(path, .{})) {
            res.append(a.dupe(u8, path) catch @panic("OOM")) catch @panic("OOM");
        } else |_| {
            std.log.err("Failed to find file: {s}", .{ path });
            unreachable;
        }
    }

    return res;
}

fn fetchLinuxSystemLibraries(a: std.mem.Allocator, b: *std.Build) std.ArrayList([]const u8) {
    // #TODO: check this is indeed a linux target
    var res = std.ArrayList([]const u8).init(a);
    const out = b.exec(&.{ "ldconfig", "-p" });
    var lines = std.mem.tokenizeScalar(u8, out, '\n');
    while (lines.next()) |line| {
        if (line.len > 0) {
            var comps = std.mem.tokenizeScalar(u8, std.mem.trim(u8, line, " \t"), ' ');
            while (comps.next()) |lib| {
                res.append(lib) catch @panic("OOM");
                break;
            }
        }
    }
    return res;
}

fn findLinuxLib(a: std.mem.Allocator, lib: []const u8, libs: std.ArrayList([]const u8)) bool {
    const full_lib_name = std.fmt.allocPrint(a, "lib{s}.so", .{ lib }) catch @panic("OOM");
    defer a.free(full_lib_name);

    for (libs.items) |alib| {
        if (std.mem.eql(u8, full_lib_name, alib)) {
            return true;
        }
    }
    return false;
}

fn buildTest(b: *std.Build, lib: *std.build.Step.Compile) void {
    const test_exe = b.addTest(.{
        .root_source_file = .{ .path = "zig-build-test/simple.zig", },
        .target = lib.target,
        .optimize = lib.optimize,
    });
    test_exe.linkLibrary(lib);
    test_exe.addIncludePath(.{ .path = "include" });

    const run_test = b.addRunArtifact(test_exe);
    const test_step = b.step("test", "Run simple test");
    test_step.dependOn(&run_test.step);
}
