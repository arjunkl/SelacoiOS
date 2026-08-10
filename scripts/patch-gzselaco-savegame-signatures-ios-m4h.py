#!/usr/bin/env python3
"""Restore the exact retail Selaco savegame virtual prototypes discovered by M4G."""

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
            "usage: patch-gzselaco-savegame-signatures-ios-m4h.py <GZSelaco source>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    events_zs = root / "wadsrc" / "static" / "zscript" / "events.zs"
    src_cmake = root / "src" / "CMakeLists.txt"

    for path in (events_zs, src_cmake):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4H prerequisite is missing: {path}")

    replace_once(
        events_zs,
        '    virtual int GetSavegameFlags() { return 0; }\n'
        '    virtual String GetSavegameTitle() { return ""; }\n'
        '    // SELACO_IOS_M4F_RETAIL_SAVEGAME_VIRTUALS\n',
        '    // Exact retail prototypes discovered by the M4G compiler diagnostic:\n'
        '    // LevelEventHandler -> StaticEventHandler, returns/arguments matched exactly.\n'
        '    virtual int GetSavegameFlags(bool quicksave, bool autosave) { return 0; }\n'
        '    virtual String, Int GetSavegameTitle(int type) { return "", 0; }\n'
        '    // SELACO_IOS_M4H_RETAIL_SAVEGAME_SIGNATURES\n',
        "replace the guessed savegame hooks with the exact retail prototypes",
    )

    replace_once(
        src_cmake,
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_OVERRIDE_SIGNATURE_DIAGNOSTICS=1)\n",
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_OVERRIDE_SIGNATURE_DIAGNOSTICS=1)\n"
        "\ttarget_compile_definitions(zdoom PRIVATE SELACO_IOS_RETAIL_SAVEGAME_SIGNATURES=1)\n",
        "identify the exact retail savegame signature build",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
