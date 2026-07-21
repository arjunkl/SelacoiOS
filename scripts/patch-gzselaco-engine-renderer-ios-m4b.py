#!/usr/bin/env python3
"""Advance the physically proven Engine Init app through renderer/title startup."""

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
    if len(sys.argv) != 2:
        print(
            "usage: patch-gzselaco-engine-renderer-ios-m4b.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    repository_root = pathlib.Path(__file__).resolve().parents[1]
    ios = root / "src" / "common" / "platform" / "ios"
    src_cmake = root / "src" / "CMakeLists.txt"
    startup = ios / "i_engine_startup_stubs.mm"
    strategy = ios / "i_engine_init_probe.mm"
    overlay = repository_root / "overlays" / "gzselaco-ios" / "i_engine_renderer_handoff.mm"
    destination = ios / "i_engine_renderer_handoff.mm"

    for path in (src_cmake, startup, strategy, overlay):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4B prerequisite is missing: {path}")
    shutil.copyfile(overlay, destination)

    replace_once(
        src_cmake,
        """set( PLAT_IOS_SOURCES
\tcommon/platform/ios/i_platform_stub.cpp
\tcommon/platform/ios/i_framebuffer.cpp
\tcommon/platform/ios/i_platform_runtime.mm
\tcommon/platform/ios/i_engine_startup_stubs.mm
\tcommon/platform/ios/i_engine_init_probe.mm )
""",
        """set( PLAT_IOS_SOURCES
\tcommon/platform/ios/i_platform_stub.cpp
\tcommon/platform/ios/i_framebuffer.cpp
\tcommon/platform/ios/i_platform_runtime.mm
\tcommon/platform/ios/i_engine_startup_stubs.mm
\tcommon/platform/ios/i_engine_init_probe.mm
\tcommon/platform/ios/i_engine_renderer_handoff.mm )
""",
        "add the iOS engine renderer handoff source",
    )
    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ENGINE_INIT_PROBE=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ENGINE_INIT_PROBE=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ENGINE_RENDERER_HANDOFF=1)\n",
        "enable the controlled engine renderer handoff",
    )

    replace_once(
        startup,
        '#include "zstring.h"\n',
        '#include "zstring.h"\n#include "i_video.h"\n#include "v_video.h"\n',
        "include the real graphics teardown contract",
    )
    replace_once(
        startup,
        """void I_ShutdownGraphics()
{
}
""",
        """void I_ShutdownGraphics()
{
    SelacoIOSReportLicensedAssetProbe(
        "engine_graphics_shutdown_entered",
        "releasing engine framebuffer and video backend");
    if (screen != nullptr) {
        DFrameBuffer *framebuffer = screen;
        screen = nullptr;
        delete framebuffer;
    }
    if (Video != nullptr) {
        delete Video;
        Video = nullptr;
    }
    SelacoIOSReportLicensedAssetProbe(
        "engine_graphics_shutdown_passed",
        "engine graphics ownership released");
}
""",
        "replace the bounded no-op graphics shutdown",
    )
    replace_once(
        strategy,
        '    return "M4A stop-before-renderer: diagnostic presenter remains sole Vulkan owner; engine stops immediately before V_Init2";\n',
        '    return "M4B diagnostic-to-engine handoff: diagnostic Vulkan is destroyed before GZSelaco creates its own Metal surface, device, swapchain, and renderer";\n',
        "update the renderer ownership strategy",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
