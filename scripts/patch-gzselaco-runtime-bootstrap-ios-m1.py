#!/usr/bin/env python3
"""Install the bounded UIKit/Vulkan runtime bootstrap into pinned GZSelaco."""

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
            "usage: patch-gzselaco-runtime-bootstrap-ios-m1.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    source_root = pathlib.Path(sys.argv[1]).resolve()
    repository_root = pathlib.Path(__file__).resolve().parents[1]
    overlay = (
        repository_root / "overlays" / "gzselaco-ios" / "i_runtime_bootstrap.mm"
    )
    src_cmake = source_root / "src" / "CMakeLists.txt"
    destination = (
        source_root
        / "src"
        / "common"
        / "platform"
        / "ios"
        / "i_platform_runtime.mm"
    )

    if not src_cmake.is_file():
        raise RuntimeError(f"not a GZSelaco source checkout: {source_root}")
    if not overlay.is_file():
        raise RuntimeError(f"runtime bootstrap overlay is missing: {overlay}")
    if not destination.parent.is_dir():
        raise RuntimeError(
            "Milestone 0 iOS source patch must run before the runtime bootstrap"
        )

    shutil.copyfile(overlay, destination)

    cmake_text = src_cmake.read_text(encoding="utf-8")
    expected_source = "\tcommon/platform/ios/i_platform_runtime.mm"
    if cmake_text.count(expected_source) != 1:
        raise RuntimeError(
            "runtime source is not selected exactly once by the iOS target"
        )

    replace_once(
        src_cmake,
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.fullengine.m0"',
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.runtime.m1"',
        "assign the runtime-bootstrap bundle identifier",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
