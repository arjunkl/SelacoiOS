#!/usr/bin/env python3
"""Run the M3 patcher with its bounded deterministic adaptations.

All ordinary replacements remain exact-one-match operations. The M2 source has
exactly two identical `StatusText(_presenter->Status())` statements, and the M3
patcher intentionally replaces both with the same combined-status expression.
This adapter permits the first of those two calls to consume one occurrence;
the second call then sees the normal exact-one-match state.

After the core M3 patch succeeds, this adapter also installs the separate iOS
startup-support translation unit required when `GameMain()` is retained instead
of dead-stripped.
"""

from __future__ import annotations

import importlib.util
import pathlib
import shutil
import sys
from types import ModuleType


DUPLICATE_DESCRIPTION = "combine initial swapchain and asset status"
DUPLICATE_TEXT = "NSString *text = StatusText(_presenter->Status());"


def load_patcher(path: pathlib.Path) -> ModuleType:
    spec = importlib.util.spec_from_file_location("selaco_m3_asset_patcher", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"unable to load M3 patcher: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def replace_exact_once(
    path: pathlib.Path,
    old: str,
    new: str,
    description: str,
) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"{description}: expected one exact match in {path}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


def install_startup_closure(
    source_root: pathlib.Path,
    repository_root: pathlib.Path,
) -> None:
    overlay = (
        repository_root
        / "overlays"
        / "gzselaco-ios"
        / "i_engine_startup_stubs.mm"
    )
    destination = (
        source_root
        / "src"
        / "common"
        / "platform"
        / "ios"
        / "i_engine_startup_stubs.mm"
    )
    src_cmake = source_root / "src" / "CMakeLists.txt"

    if not overlay.is_file():
        raise RuntimeError(f"M3 startup closure overlay is missing: {overlay}")
    if not destination.parent.is_dir() or not src_cmake.is_file():
        raise RuntimeError("M3 startup closure prerequisites are missing")

    shutil.copyfile(overlay, destination)
    replace_exact_once(
        src_cmake,
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm )\n",
        "set( PLAT_IOS_SOURCES\n"
        "\tcommon/platform/ios/i_platform_stub.cpp\n"
        "\tcommon/platform/ios/i_framebuffer.cpp\n"
        "\tcommon/platform/ios/i_platform_runtime.mm\n"
        "\tcommon/platform/ios/i_engine_startup_stubs.mm )\n",
        "add the iOS engine-startup platform closure",
    )


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: run-m3-local-asset-patcher.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    script_dir = pathlib.Path(__file__).resolve().parent
    repository_root = script_dir.parent
    source_root = pathlib.Path(sys.argv[1]).resolve()
    patcher_path = script_dir / "patch-gzselaco-local-asset-ios-m3.py"
    if not patcher_path.is_file():
        raise RuntimeError(f"M3 patcher is missing: {patcher_path}")

    module = load_patcher(patcher_path)

    def strict_with_one_known_duplicate(
        path: pathlib.Path,
        old: str,
        new: str,
        description: str,
    ) -> None:
        text = path.read_text(encoding="utf-8")
        count = text.count(old)
        if (
            description == DUPLICATE_DESCRIPTION
            and old == DUPLICATE_TEXT
            and count == 2
        ):
            path.write_text(text.replace(old, new, 1), encoding="utf-8")
            return
        if count != 1:
            raise RuntimeError(
                f"{description}: expected one exact match in {path}, found {count}"
            )
        path.write_text(text.replace(old, new, 1), encoding="utf-8")

    module.replace_once = strict_with_one_known_duplicate
    original_argv = sys.argv
    try:
        sys.argv = [str(patcher_path), str(source_root)]
        result = int(module.main())
    finally:
        sys.argv = original_argv

    if result != 0:
        return result

    install_startup_closure(source_root, repository_root)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
