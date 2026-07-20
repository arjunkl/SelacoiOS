#!/usr/bin/env python3
"""Run the M3 patcher while handling its two identical M2 status lines.

All ordinary replacements remain exact-one-match operations. The M2 source has
exactly two identical `StatusText(_presenter->Status())` statements, and the M3
patcher intentionally replaces both with the same combined-status expression.
This adapter permits the first of those two calls to consume one occurrence;
the second call then sees the normal exact-one-match state.
"""

from __future__ import annotations

import importlib.util
import pathlib
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


def main() -> int:
    if len(sys.argv) != 2:
        print(
            "usage: run-m3-local-asset-patcher.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    script_dir = pathlib.Path(__file__).resolve().parent
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
        sys.argv = [str(patcher_path), original_argv[1]]
        return int(module.main())
    finally:
        sys.argv = original_argv


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
