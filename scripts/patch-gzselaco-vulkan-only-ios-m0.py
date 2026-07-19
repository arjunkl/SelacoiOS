#!/usr/bin/env python3
"""Apply Vulkan-only and iOS-safe link selection to the bounded engine target."""

from __future__ import annotations

import pathlib
import shutil
import sys


def replace_once(path: pathlib.Path, old: str, new: str, description: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{description}: expected one exact match in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        print(
            "usage: patch-gzselaco-vulkan-only-ios-m0.py <GZSelaco source> <iOS runtime overlay>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    runtime_overlay = pathlib.Path(sys.argv[2]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    if not src_cmake.is_file():
        raise RuntimeError(f"not a GZSelaco source checkout: {root}")
    if not runtime_overlay.is_file():
        raise RuntimeError(f"iOS runtime overlay is missing: {runtime_overlay}")

    ios_sources = (
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp )\n"
    )
    ios_sources_with_runtime = (
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm )\n"
    )
    replace_once(
        src_cmake,
        ios_sources,
        ios_sources_with_runtime,
        "add the native iOS runtime closure to the platform source set",
    )

    marker = (
        "\tutility/nodebuilder/nodebuild_gl.cpp\n"
        "\tutility/nodebuilder/nodebuild_utility.cpp\n"
        ")\n\n"
        "if( ${HAVE_VM_JIT} )\n"
    )
    desktop_gl_sources = (
        "common/rendering/gl_load/gl_interface.cpp\n"
        "common/rendering/gl/gl_renderer.cpp\n"
        "common/rendering/gl/gl_stereo3d.cpp\n"
        "common/rendering/gl/gl_framebuffer.cpp\n"
        "common/rendering/gl/gl_renderstate.cpp\n"
        "common/rendering/gl/gl_renderbuffers.cpp\n"
        "common/rendering/gl/gl_postprocess.cpp\n"
        "common/rendering/gl/gl_postprocessstate.cpp\n"
        "common/rendering/gl/gl_debug.cpp\n"
        "common/rendering/gl/gl_buffers.cpp\n"
        "common/rendering/gl/gl_hwtexture.cpp\n"
        "common/rendering/gl/gl_samplers.cpp\n"
        "common/rendering/gl/gl_shader.cpp\n"
        "common/rendering/gl/gl_shaderprogram.cpp\n"
    )
    removal_block = (
        "\tutility/nodebuilder/nodebuild_gl.cpp\n"
        "\tutility/nodebuilder/nodebuild_utility.cpp\n"
        ")\n\n"
        "if(CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "\tmessage(STATUS \"SelacoiOS: desktop OpenGL renderer sources excluded\")\n"
        "\tlist(REMOVE_ITEM FASTMATH_SOURCES\n"
        "\t\tcommon/rendering/gl_load/gl_load.c)\n"
        "\tlist(REMOVE_ITEM PCH_SOURCES\n"
        + "".join(f"\t\t{source}" for source in desktop_gl_sources.splitlines(keepends=True))
        + "\t)\n"
        "endif()\n\n"
        "if( ${HAVE_VM_JIT} )\n"
    )
    replace_once(
        src_cmake,
        marker,
        removal_block,
        "insert the Vulkan-only iOS source selection",
    )

    clock_block = (
        "if( UNIX )\n"
        "\tCHECK_LIBRARY_EXISTS( rt clock_gettime \"\" CLOCK_GETTIME_IN_RT )\n"
        "\tif( NOT CLOCK_GETTIME_IN_RT )\n"
        "\t\tCHECK_FUNCTION_EXISTS( clock_gettime CLOCK_GETTIME_EXISTS )\n"
        "\t\tif( NOT CLOCK_GETTIME_EXISTS )\n"
        "\t\t\tmessage( STATUS \"Could not find clock_gettime. Timing statistics will not be available.\" )\n"
        "\t\t\tadd_definitions( -DNO_CLOCK_GETTIME )\n"
        "\t\tendif()\n"
        "\telse()\n"
        "\t\tlist( APPEND PROJECT_LIBRARIES rt )\n"
        "\tendif()\n"
        "endif()\n"
    )
    ios_clock_block = (
        "if( UNIX AND NOT CMAKE_SYSTEM_NAME STREQUAL \"iOS\" )\n"
        "\tCHECK_LIBRARY_EXISTS( rt clock_gettime \"\" CLOCK_GETTIME_IN_RT )\n"
        "\tif( NOT CLOCK_GETTIME_IN_RT )\n"
        "\t\tCHECK_FUNCTION_EXISTS( clock_gettime CLOCK_GETTIME_EXISTS )\n"
        "\t\tif( NOT CLOCK_GETTIME_EXISTS )\n"
        "\t\t\tmessage( STATUS \"Could not find clock_gettime. Timing statistics will not be available.\" )\n"
        "\t\t\tadd_definitions( -DNO_CLOCK_GETTIME )\n"
        "\t\tendif()\n"
        "\telse()\n"
        "\t\tlist( APPEND PROJECT_LIBRARIES rt )\n"
        "\tendif()\n"
        "endif()\n"
        "if(CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "\tmessage(STATUS \"SelacoiOS: librt excluded; clock_gettime is provided by iOS\")\n"
        "endif()\n"
    )
    replace_once(
        src_cmake,
        clock_block,
        ios_clock_block,
        "exclude the nonexistent librt dependency from iOS",
    )

    runtime_destination = (
        root / "src" / "common" / "platform" / "ios" / "i_platform_runtime.mm"
    )
    shutil.copyfile(runtime_overlay, runtime_destination)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
