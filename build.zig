const std = @import("std");
const Translator = @import("translate_c").Translator;

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    const options = .{
        .shared = b.option(
            bool,
            "shared",
            "Build GLFW as shared lib",
        ) orelse false,
        .enable_x11 = b.option(
            bool,
            "x11",
            "Whether to build with X11 support (default: true)",
        ) orelse true,
        .enable_wayland = b.option(
            bool,
            "wayland",
            "Whether to build with Wayland support (default: true)",
        ) orelse true,
        .enable_vulkan_import = b.option(
            bool,
            "import_vulkan",
            "Whether to build with external Vulkan dependency (default: false)",
        ) orelse false,
    };

    const options_step = b.addOptions();
    const opt_info = @typeInfo(@TypeOf(options)).@"struct";
    inline for (opt_info.field_names, opt_info.field_types) |field_name, field_type| {
        options_step.addOption(field_type, field_name, @field(options, field_name));
    }

    const options_module = options_step.createModule();

    const translate_c_dep = b.dependency("translate_c", .{});

    const translate_c: Translator = .init(translate_c_dep, .{
        .c_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
        .default_init = true,
    });
    translate_c.addIncludePath(b.path("libs/glfw/include"));
    const c_module = translate_c.mod;

    const module = b.addModule("root", .{
        .root_source_file = b.path("src/zglfw.zig"),
        .imports = &.{
            .{ .name = "zglfw_options", .module = options_module },
            .{ .name = "c", .module = c_module },
        },
    });

    if (target.result.os.tag == .emscripten) return;

    const glfw = b.addLibrary(.{
        .name = "glfw",
        .linkage = if (options.shared) .dynamic else .static,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
    });

    if (options.shared and target.result.os.tag == .windows) {
        glfw.root_module.addCMacro("_GLFW_BUILD_DLL", "");
    }

    b.installArtifact(glfw);
    glfw.installHeadersDirectory(b.path("libs/glfw/include"), "", .{});

    addIncludePaths(b, glfw.root_module, target, options);
    addIncludePaths(b, translate_c, target, options);
    linkSystemLibs(b, glfw, target, options);

    const src_dir_path = b.path("libs/glfw/src");
    switch (target.result.os.tag) {
        .windows => {
            glfw.root_module.addCSourceFiles(.{
                .root = src_dir_path,
                .files = &.{
                    "platform.c",
                    "monitor.c",
                    "init.c",
                    "vulkan.c",
                    "input.c",
                    "context.c",
                    "window.c",
                    "osmesa_context.c",
                    "egl_context.c",
                    "null_init.c",
                    "null_monitor.c",
                    "null_window.c",
                    "null_joystick.c",
                    "wgl_context.c",
                    "win32_thread.c",
                    "win32_init.c",
                    "win32_monitor.c",
                    "win32_time.c",
                    "win32_joystick.c",
                    "win32_window.c",
                    "win32_module.c",
                },
                .flags = &.{"-D_GLFW_WIN32"},
            });
        },
        .macos => {
            glfw.root_module.addCSourceFiles(.{
                .root = src_dir_path,
                .files = &.{
                    "platform.c",
                    "monitor.c",
                    "init.c",
                    "vulkan.c",
                    "input.c",
                    "context.c",
                    "window.c",
                    "osmesa_context.c",
                    "egl_context.c",
                    "null_init.c",
                    "null_monitor.c",
                    "null_window.c",
                    "null_joystick.c",
                    "posix_thread.c",
                    "posix_module.c",
                    "posix_poll.c",
                    "nsgl_context.m",
                    "cocoa_time.c",
                    "cocoa_joystick.m",
                    "cocoa_init.m",
                    "cocoa_window.m",
                    "cocoa_monitor.m",
                },
                .flags = &.{"-D_GLFW_COCOA"},
            });
        },
        .linux => {
            glfw.root_module.addCSourceFiles(.{
                .root = src_dir_path,
                .files = &.{
                    "platform.c",
                    "monitor.c",
                    "init.c",
                    "vulkan.c",
                    "input.c",
                    "context.c",
                    "window.c",
                    "osmesa_context.c",
                    "egl_context.c",
                    "null_init.c",
                    "null_monitor.c",
                    "null_window.c",
                    "null_joystick.c",
                    "posix_time.c",
                    "posix_thread.c",
                    "posix_module.c",
                },
                .flags = &.{},
            });
            if (options.enable_x11 or options.enable_wayland) {
                glfw.root_module.addCSourceFiles(.{
                    .root = src_dir_path,
                    .files = &.{
                        "xkb_unicode.c",
                        "linux_joystick.c",
                        "posix_poll.c",
                    },
                    .flags = &.{},
                });
            }
            if (options.enable_x11) {
                glfw.root_module.addCSourceFiles(.{
                    .root = src_dir_path,
                    .files = &.{
                        "x11_init.c",
                        "x11_monitor.c",
                        "x11_window.c",
                        "glx_context.c",
                    },
                    .flags = &.{},
                });
                glfw.root_module.addCMacro("_GLFW_X11", "1");
                glfw.root_module.linkSystemLibrary("X11", .{});
            }
            if (options.enable_wayland) {
                glfw.root_module.addCSourceFiles(.{
                    .root = src_dir_path,
                    .files = &.{
                        "wl_init.c",
                        "wl_monitor.c",
                        "wl_window.c",
                    },
                    .flags = &.{},
                });
                glfw.root_module.addIncludePath(src_dir_path.path(b, "wayland"));
                glfw.root_module.addCMacro("_GLFW_WAYLAND", "1");
            }
        },
        else => {},
    }
    addIncludePaths(b, module, target, options);

    const test_step = b.step("test", "Run zglfw tests");
    const tests = b.addTest(.{
        .name = "zglfw-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zglfw.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zglfw_options", .module = options_module },
                .{ .name = "c", .module = c_module },
            },
        }),
    });
    addIncludePaths(b, tests.root_module, target, options);
    linkSystemLibs(b, tests, target, options);
    tests.root_module.linkLibrary(glfw);
    b.installArtifact(tests);
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

fn addIncludePaths(b: *std.Build, unit: anytype, target: std.Build.ResolvedTarget, options: anytype) void {
    switch (target.result.os.tag) {
        .linux => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                unit.addSystemIncludePath(system_sdk.path("linux/include"));
                if (options.enable_wayland) {
                    unit.addSystemIncludePath(system_sdk.path("linux/include/wayland"));
                }
            }
        },
        else => {},
    }
}

fn linkSystemLibs(b: *std.Build, compile_step: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, options: anytype) void {
    compile_step.root_module.link_libc = true;
    switch (target.result.os.tag) {
        .windows => {
            compile_step.root_module.linkSystemLibrary("gdi32", .{});
            compile_step.root_module.linkSystemLibrary("user32", .{});
            compile_step.root_module.linkSystemLibrary("shell32", .{});
        },
        .macos => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                compile_step.root_module.addFrameworkPath(system_sdk.path("macos12/System/Library/Frameworks"));
                compile_step.root_module.addSystemIncludePath(system_sdk.path("macos12/usr/include"));
                compile_step.root_module.addLibraryPath(system_sdk.path("macos12/usr/lib"));
            }
            compile_step.root_module.linkSystemLibrary("objc", .{});
            compile_step.root_module.linkFramework("IOKit", .{});
            compile_step.root_module.linkFramework("CoreFoundation", .{});
            compile_step.root_module.linkFramework("Metal", .{});
            compile_step.root_module.linkFramework("AppKit", .{});
            compile_step.root_module.linkFramework("CoreServices", .{});
            compile_step.root_module.linkFramework("CoreGraphics", .{});
            compile_step.root_module.linkFramework("Foundation", .{});
        },
        .linux => {
            if (b.lazyDependency("system_sdk", .{})) |system_sdk| {
                if (target.result.cpu.arch.isX86()) {
                    compile_step.root_module.addLibraryPath(system_sdk.path("linux/lib/x86_64-linux-gnu"));
                } else {
                    compile_step.root_module.addLibraryPath(system_sdk.path("linux/lib/aarch64-linux-gnu"));
                }
                compile_step.root_module.addSystemIncludePath(system_sdk.path("linux/include"));
                compile_step.root_module.addSystemIncludePath(system_sdk.path("linux/include/wayland"));
            }
            if (options.enable_x11) {
                compile_step.root_module.addCMacro("_GLFW_X11", "1");
                compile_step.root_module.linkSystemLibrary("X11", .{});
            }
            if (options.enable_wayland) {
                compile_step.root_module.addCMacro("_GLFW_WAYLAND", "1");
            }
        },
        else => {},
    }
}
