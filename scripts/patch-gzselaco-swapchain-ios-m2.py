#!/usr/bin/env python3
"""Install the bounded Milestone 2 swapchain presenter into patched GZSelaco."""

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
            "usage: patch-gzselaco-swapchain-ios-m2.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    source_root = pathlib.Path(sys.argv[1]).resolve()
    repository_root = pathlib.Path(__file__).resolve().parents[1]
    overlay = repository_root / "overlays" / "gzselaco-ios" / "i_swapchain_probe.mm"
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
        raise RuntimeError(f"swapchain overlay is missing: {overlay}")
    if not destination.parent.is_dir():
        raise RuntimeError(
            "Milestone 1 runtime patch must run before the Milestone 2 patch"
        )

    cmake_text = src_cmake.read_text(encoding="utf-8")
    required_markers = (
        "MOLTENVK_DYNAMIC_FRAMEWORK",
        '@executable_path/Frameworks',
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.runtime.m1"',
    )
    for marker in required_markers:
        if marker not in cmake_text:
            raise RuntimeError(
                f"Milestone 1 dynamic-MoltenVK boundary is missing marker: {marker}"
            )

    shutil.copyfile(overlay, destination)

    replace_once(
        src_cmake,
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.runtime.m1"',
        'XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.swapchain.m2"',
        "assign the Milestone 2 swapchain bundle identifier",
    )

    generated = destination.read_text(encoding="utf-8")
    required_source_markers = (
        "SelacoiOS Milestone 2",
        "vkCreateSwapchainKHR",
        "vkQueuePresentKHR",
        "phase=m2_first_frame_presented",
        "No GZSelaco game loop started",
    )
    for marker in required_source_markers:
        if marker not in generated:
            raise RuntimeError(f"swapchain source lacks required marker: {marker}")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
