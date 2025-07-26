const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Options.
    const ktx_feature_etc_unpack = b.option(bool, "etc_unpack", "ETC decoding support.") orelse true;
    const ktx_feature_ktx1 = b.option(bool, "ktx1", "Enable KTX 1 support.") orelse true;
    const ktx_feature_ktx2 = b.option(bool, "ktx2", "Enable KTX 2 support.") orelse true;
    const ktx_feature_vk_upload = b.option(bool, "vk_upload", "Enable Vulkan texture upload.") orelse true;
    const ktx_feature_gl_upload = b.option(bool, "gl_upload", "Enable OpenGL texture upload.") orelse true;
    const basisu_support_sse = b.option(bool, "basisu_sse", "Compile with SSE support for BasisU.") orelse target.result.cpu.arch.isX86();
    const basisu_support_opencl = b.option(bool, "basisu_opencl", "Compile with OpenCL support for BasisU.") orelse false;

    // version.h
    const version_header = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "version.h",
    }, .{
        .KTX_VERSION_MAJOR = 4,
        .KTX_VERSION_MINOR = 0,
        .KTX_VERSION_PATCH = 0,
        .KTX_VERSION_SCM = "",
    });

    // ASTC.
    const astc_encoder_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    const astc_encoder_lib = b.addLibrary(.{
        .name = "astc-encoder",
        .root_module = astc_encoder_module,
    });
    configureAstcEncoder(b, astc_encoder_lib);

    // KTX.
    const ktx_module = b.createModule(.{
        .target = target,
        .optimize = optimize,
    });
    const ktx_lib = b.addLibrary(.{
        .name = "ktx",
        .root_module = ktx_module,
    });

    configureKtx(b, ktx_lib, version_header, .{
        .etc_unpack = ktx_feature_etc_unpack,
        .ktx1 = ktx_feature_ktx1,
        .ktx2 = ktx_feature_ktx2,
        .vk_upload = ktx_feature_vk_upload,
        .gl_upload = ktx_feature_gl_upload,
        .basisu_sse = basisu_support_sse,
        .basisu_opencl = basisu_support_opencl,
    });

    ktx_lib.root_module.linkLibrary(astc_encoder_lib);

    b.installArtifact(ktx_lib);

    // Module.
    const main_header = if (ktx_feature_vk_upload) blk: {
        const wrapper = b.addWriteFile("loadvulkan.h",
            \\#include "vulkan/vulkan.h"
            \\#include "ktxvulkan.h"
        );
        break :blk wrapper.getDirectory().path(b, "loadvulkan.h");
    } else b.path("include/ktx.h");

    const ktx_zig_module_step = b.addTranslateC(.{
        .root_source_file = main_header,
        .target = target,
        .optimize = optimize,
    });
    ktx_zig_module_step.addIncludePath(b.path("include"));
    ktx_zig_module_step.addIncludePath(b.path("external/dfdutils"));

    if (ktx_feature_vk_upload) {
        ktx_lib.root_module.linkSystemLibrary("vulkan", .{});

        const vulkan_headers_dep = b.dependency("vulkan_headers", .{});
        ktx_zig_module_step.addIncludePath(vulkan_headers_dep.path("include"));
    }

    _ = ktx_zig_module_step.addModule("libktx");
}

const KtxOptions = struct {
    etc_unpack: bool,
    ktx1: bool,
    ktx2: bool,
    vk_upload: bool,
    gl_upload: bool,
    basisu_sse: bool,
    basisu_opencl: bool,
};

fn configureKtx(b: *std.Build, lib: *std.Build.Step.Compile, version_header: *std.Build.Step.ConfigHeader, options: KtxOptions) void {
    lib.root_module.link_libc = true;
    lib.root_module.link_libcpp = true;
    lib.root_module.addConfigHeader(version_header);

    if (lib.rootModuleTarget().os.tag == .linux) {
        lib.root_module.linkSystemLibrary("dl", .{});
        lib.root_module.linkSystemLibrary("pthread", .{});
    }

    // Include paths.
    lib.root_module.addIncludePath(b.path("include"));
    lib.root_module.addIncludePath(b.path("lib"));
    lib.root_module.addIncludePath(b.path("external"));
    lib.root_module.addIncludePath(b.path("utils"));
    lib.root_module.addIncludePath(b.path("external/basisu/transcoder"));
    lib.root_module.addIncludePath(b.path("external/basisu"));
    lib.root_module.addIncludePath(b.path("external/dfdutils"));
    lib.root_module.addIncludePath(b.path("external/basisu/zstd"));
    lib.root_module.addSystemIncludePath(b.path("other_include"));

    // Defines.
    lib.root_module.addCMacro("LIBKTX", "1");
    lib.root_module.addCMacro("KTX_FEATURE_WRITE", "1");
    lib.root_module.addCMacro("BASISD_SUPPORT_KTX2", "1");
    lib.root_module.addCMacro("BASISD_SUPPORT_KTX2_ZSTD", "0");
    lib.root_module.addCMacro("BASISD_SUPPORT_FXT1", "0");

    if (options.etc_unpack) {
        lib.root_module.addCMacro("SUPPORT_SOFTWARE_ETC_UNPACK", "1");
    }
    if (options.ktx1) {
        lib.root_module.addCMacro("KTX_FEATURE_KTX1", "1");
    }
    if (options.ktx2) {
        lib.root_module.addCMacro("KTX_FEATURE_KTX2", "1");
    }
    if (!options.vk_upload) {
        lib.root_module.addCMacro("KTX_OMIT_VULKAN", "1");
    }
    if (options.basisu_sse) {
        lib.root_module.addCMacro("BASISU_SUPPORT_SSE", "1");
    } else {
        lib.root_module.addCMacro("BASISU_SUPPORT_SSE", "0");
    }
    if (options.basisu_opencl) {
        lib.root_module.addCMacro("BASISU_SUPPORT_OPENCL", "1");
        lib.root_module.linkSystemLibrary("OpenCL", .{});
    } else {
        lib.root_module.addCMacro("BASISU_SUPPORT_OPENCL", "0");
    }

    // Sources.
    var all_sources = std.ArrayList([]const u8).init(b.allocator);
    defer all_sources.deinit();

    all_sources.appendSlice(&.{
        "lib/astc_codec.cpp",
        "lib/basis_transcode.cpp",
        "lib/miniz_wrapper.cpp",
        "external/basisu/zstd/zstd.c",
        "lib/checkheader.c",
        "external/dfdutils/createdfd.c",
        "external/dfdutils/colourspaces.c",
        "external/dfdutils/interpretdfd.c",
        "external/dfdutils/printdfd.c",
        "external/dfdutils/queries.c",
        "external/dfdutils/vk2dfd.c",
        "lib/filestream.c",
        "lib/hashlist.c",
        "lib/info.c",
        "lib/memstream.c",
        "lib/strings.c",
        "lib/swap.c",
        "lib/texture.c",
        "lib/texture2.c",
        "lib/vkformat_check.c",
        "lib/vkformat_check_variant.c",
        "lib/vkformat_str.c",
        "lib/vkformat_typesize.c",
        // writer part.
        "lib/basis_encode.cpp",
        "lib/writer1.c",
        "lib/writer2.c",
    }) catch @panic("OOM");

    if (options.etc_unpack) {
        all_sources.append("external/etcdec/etcdec.cxx") catch @panic("OOM");
    }
    if (options.ktx1) {
        all_sources.append("lib/texture1.c") catch @panic("OOM");
    }
    if (options.gl_upload) {
        all_sources.appendSlice(&.{ "lib/gl_funcs.c", "lib/glloader.c" }) catch @panic("OOM");
    }
    if (options.vk_upload) {
        all_sources.appendSlice(&.{ "lib/vk_funcs.c", "lib/vkloader.c" }) catch @panic("OOM");
        lib.root_module.addIncludePath(b.path("external/dfdutils"));
    }

    lib.root_module.addCSourceFiles(.{ .files = all_sources.items });

    const basisu_encoder_cxx_src = [_][]const u8{
        "external/basisu/transcoder/basisu_transcoder.cpp",
        "external/basisu/encoder/basisu_backend.cpp",
        "external/basisu/encoder/basisu_basis_file.cpp",
        "external/basisu/encoder/basisu_bc7enc.cpp",
        "external/basisu/encoder/basisu_comp.cpp",
        "external/basisu/encoder/basisu_enc.cpp",
        "external/basisu/encoder/basisu_etc.cpp",
        "external/basisu/encoder/basisu_frontend.cpp",
        "external/basisu/encoder/basisu_gpu_texture.cpp",
        "external/basisu/encoder/basisu_opencl.cpp",
        "external/basisu/encoder/basisu_pvrtc1_4.cpp",
        "external/basisu/encoder/basisu_resample_filters.cpp",
        "external/basisu/encoder/basisu_resampler.cpp",
        "external/basisu/encoder/basisu_ssim.cpp",
        "external/basisu/encoder/basisu_uastc_enc.cpp",
    };

    const basisu_flags = &.{
        "-std=gnu++11",
        "-w",
    };
    lib.root_module.addCSourceFiles(.{ .files = &basisu_encoder_cxx_src, .flags = basisu_flags });

    if (options.basisu_sse and lib.rootModuleTarget().cpu.arch.isX86()) {
        // It's kind of a workaround.
        var sse_flags = std.ArrayList([]const u8).init(b.allocator);
        defer sse_flags.deinit();
        sse_flags.appendSlice(basisu_flags) catch @panic("OOM");
        sse_flags.appendSlice(&.{
            "-D__SSE4_1__",
            "-D__SSSE3__",
            "-D__SSE3__",

            "-mno-avx",
            "-U__AVX__",
            "-U__AVX2__",
            "-U__AVX512F__",
        }) catch @panic("OOM");
        lib.root_module.addCSourceFile(.{ .file = b.path("external/basisu/encoder/basisu_kernels_sse.cpp"), .flags = sse_flags.items });
    }
}

fn configureAstcEncoder(b: *std.Build, lib: *std.Build.Step.Compile) void {
    lib.root_module.link_libcpp = true;
    lib.root_module.addIncludePath(b.path("external/astc-encoder/Source"));

    const astc_sources = &.{
        "external/astc-encoder/Source/astcenc_averages_and_directions.cpp",
        "external/astc-encoder/Source/astcenc_block_sizes.cpp",
        "external/astc-encoder/Source/astcenc_color_quantize.cpp",
        "external/astc-encoder/Source/astcenc_color_unquantize.cpp",
        "external/astc-encoder/Source/astcenc_compress_symbolic.cpp",
        "external/astc-encoder/Source/astcenc_compute_variance.cpp",
        "external/astc-encoder/Source/astcenc_decompress_symbolic.cpp",
        "external/astc-encoder/Source/astcenc_entry.cpp",
        "external/astc-encoder/Source/astcenc_find_best_partitioning.cpp",
        "external/astc-encoder/Source/astcenc_ideal_endpoints_and_weights.cpp",
        "external/astc-encoder/Source/astcenc_image.cpp",
        "external/astc-encoder/Source/astcenc_integer_sequence.cpp",
        "external/astc-encoder/Source/astcenc_mathlib.cpp",
        "external/astc-encoder/Source/astcenc_mathlib_softfloat.cpp",
        "external/astc-encoder/Source/astcenc_partition_tables.cpp",
        "external/astc-encoder/Source/astcenc_percentile_tables.cpp",
        "external/astc-encoder/Source/astcenc_pick_best_endpoint_format.cpp",
        "external/astc-encoder/Source/astcenc_platform_isa_detection.cpp",
        "external/astc-encoder/Source/astcenc_quantization.cpp",
        "external/astc-encoder/Source/astcenc_symbolic_physical.cpp",
        "external/astc-encoder/Source/astcenc_weight_align.cpp",
        "external/astc-encoder/Source/astcenc_weight_quant_xfer_tables.cpp",
        "external/astc-encoder/Source/wuffs-v0.3.c",
    };
    lib.root_module.addCSourceFiles(.{
        .files = astc_sources,
    });

    const AstcIsa = enum { none, sse2, sse41, avx2, neon };
    const target_arch = lib.rootModuleTarget().cpu.arch;
    const default_isa: AstcIsa = if (target_arch == .x86_64) .avx2 else if (target_arch.isAARCH64()) .neon else .none;
    const astc_isa = b.option(AstcIsa, "astc_isa", "ASTC encoder ISA") orelse default_isa;

    switch (astc_isa) {
        .none => {},
        .sse2 => lib.root_module.addCMacro("ASTCENC_SSE", "20"),
        .sse41 => lib.root_module.addCMacro("ASTCENC_SSE", "41"),
        .avx2 => lib.root_module.addCMacro("ASTCENC_AVX", "2"),
        .neon => lib.root_module.addCMacro("ASTCENC_NEON", "1"),
    }
}
