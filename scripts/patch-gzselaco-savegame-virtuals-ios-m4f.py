#!/usr/bin/env python3
"""Restore the retail Selaco savegame virtual contract for title/menu startup."""

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
            "usage: patch-gzselaco-savegame-virtuals-ios-m4f.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    events_zs = root / "wadsrc" / "static" / "zscript" / "events.zs"
    src_cmake = root / "src" / "CMakeLists.txt"

    for path in (events_zs, src_cmake):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4F prerequisite is missing: {path}")

    replace_once(
        events_zs,
        '    virtual\tString, Int GetSavegameComment() { return "", 0; }\t              // @Cockatrice - Supply additional information to the savegame comment field during a save\n',
        '    virtual\tString, Int GetSavegameComment() { return "", 0; }\t              // @Cockatrice - Supply additional information to the savegame comment field during a save\n'
        '    // Selaco retail compatibility. The licensed game scripts override these\n'
        '    // hooks, but the pinned public engine support archive omitted their base\n'
        '    // declarations. Safe defaults preserve existing public-engine behavior.\n'
        '    virtual int GetSavegameFlags() { return 0; }\n'
        '    virtual String GetSavegameTitle() { return ""; }\n'
        '    // SELACO_IOS_M4F_RETAIL_SAVEGAME_VIRTUALS\n',
        "restore the retail savegame virtual declarations",
    )

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ZSCRIPT_DIAGNOSTICS=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_ZSCRIPT_DIAGNOSTICS=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_RETAIL_SAVEGAME_VIRTUALS=1)\n",
        "identify the retail savegame compatibility build",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
