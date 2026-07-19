#!/usr/bin/env python3
"""Remove desktop OpenGL translation units from the bounded iOS compile target."""

from __future__ import annotations

import pathlib
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
    if len(sys.argv) != 2:
        print(
            "usage: patch-gzselaco-vulkan-only-ios-m0.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    src_cmake = root / "src" / "CMakeLists.txt"
    if not src_cmake.is_file():
        raise RuntimeError(f"not a GZSelaco source checkout: {root}")

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
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
