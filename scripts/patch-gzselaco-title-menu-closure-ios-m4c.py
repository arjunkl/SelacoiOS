#!/usr/bin/env python3
"""Close the bounded iOS title/menu platform symbols exposed by M4B."""

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
            "usage: patch-gzselaco-title-menu-closure-ios-m4c.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    repository_root = pathlib.Path(__file__).resolve().parents[1]
    ios = root / "src" / "common" / "platform" / "ios"
    src_cmake = root / "src" / "CMakeLists.txt"
    d_main = root / "src" / "d_main.cpp"
    statdb = root / "src" / "common" / "thirdparty" / "statdb.cpp"
    overlay = repository_root / "overlays" / "gzselaco-ios" / "i_title_menu_closure.cpp"
    destination = ios / "i_title_menu_closure.cpp"

    for path in (src_cmake, d_main, statdb, overlay):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4C prerequisite is missing: {path}")

    shutil.copyfile(overlay, destination)

    replace_once(
        src_cmake,
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm\n"
        "\tcommon/platform/ios/i_engine_startup_stubs.mm\n"
        "\tcommon/platform/ios/i_engine_init_probe.mm\n"
        "\tcommon/platform/ios/i_engine_renderer_handoff.mm )\n",
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm\n"
        "\tcommon/platform/ios/i_engine_startup_stubs.mm\n"
        "\tcommon/platform/ios/i_engine_init_probe.mm\n"
        "\tcommon/platform/ios/i_engine_renderer_handoff.mm\n"
        "\tcommon/platform/ios/i_title_menu_closure.cpp )\n",
        "add the separate iOS title/menu closure source",
    )
    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ENGINE_RENDERER_HANDOFF=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ENGINE_RENDERER_HANDOFF=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_TITLE_MENU_CLOSURE=1)\n",
        "enable the bounded title/menu platform closure",
    )

    replace_once(
        d_main,
        "\t\tStartWindow = FStartupScreen::CreateInstance (TexMan.GuesstimateNumTextures() + 5);\n",
        "#if defined(SELACO_IOS_TITLE_MENU_CLOSURE)\n"
        "\t\tSelacoIOSReportLicensedAssetProbe(\"native_startup_window_bypassed\", \"using inert FStartupScreen base while engine-rendered startup remains active\");\n"
        "\t\tStartWindow = new FStartupScreen(TexMan.GuesstimateNumTextures() + 5);\n"
        "#else\n"
        "\t\tStartWindow = FStartupScreen::CreateInstance (TexMan.GuesstimateNumTextures() + 5);\n"
        "#endif\n",
        "replace the desktop native startup window with its inert base implementation",
    )

    replace_once(
        statdb,
        "#ifdef WIN32\n",
        "#if defined(SELACO_IOS_TITLE_MENU_CLOSURE)\n"
        "void StatDatabase::init() { pipe = nullptr; }\n"
        "bool StatDatabase::checkConnection() { return false; }\n"
        "bool StatDatabase::isConnected() { return false; }\n"
        "bool StatDatabase::connectRPC() { return false; }\n"
        "void StatDatabase::disconnectRPC() { pipe = nullptr; }\n"
        "bool StatDatabase::writeRPC(const void*, size_t) { return false; }\n"
        "bool StatDatabase::readRPC(void*, size_t) { return false; }\n"
        "#endif\n\n"
        "#ifdef WIN32\n",
        "add the explicit iOS null statistics transport",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
