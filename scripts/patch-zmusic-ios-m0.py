#!/usr/bin/env python3
"""Apply the bounded Milestone 0 iOS compatibility edits to pinned ZMusic."""

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
            "usage: patch-zmusic-ios-m0.py <ZMusic source directory> <FluidSynth stub>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    stub_source = pathlib.Path(sys.argv[2]).resolve()
    if not (root / "CMakeLists.txt").is_file():
        raise RuntimeError(f"not a ZMusic source checkout: {root}")
    if not stub_source.is_file():
        raise RuntimeError(f"FluidSynth stub is missing: {stub_source}")

    replace_once(
        root / "CMakeLists.txt",
        '\tif(APPLE)\n\t\tset(CMAKE_OSX_DEPLOYMENT_TARGET "10.9")\n',
        '\tif(APPLE)\n'
        '\t\tif(NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n'
        '\t\t\tset(CMAKE_OSX_DEPLOYMENT_TARGET "10.9")\n'
        '\t\tendif()\n',
        "guard the macOS deployment target from iOS",
    )

    replace_once(
        root / "thirdparty" / "CMakeLists.txt",
        "add_subdirectory(fluidsynth/src)\n",
        'option(ZMUSIC_ENABLE_FLUIDSYNTH "Build the bundled FluidSynth backend" ON)\n'
        "if(ZMUSIC_ENABLE_FLUIDSYNTH)\n"
        "\tadd_subdirectory(fluidsynth/src)\n"
        "endif()\n",
        "make FluidSynth an explicit optional backend",
    )

    source_cmake = root / "source" / "CMakeLists.txt"
    replace_once(
        source_cmake,
        "\tmididevices/music_fluidsynth_mididevice.cpp\n",
        "",
        "remove unconditional FluidSynth MIDI source selection",
    )
    replace_once(
        source_cmake,
        "target_sources(zmusic-obj INTERFACE ${HEADER_FILES})\n",
        "target_sources(zmusic-obj INTERFACE ${HEADER_FILES})\n\n"
        "if(ZMUSIC_ENABLE_FLUIDSYNTH)\n"
        "\ttarget_sources(zmusic-obj INTERFACE\n"
        "\t\tmididevices/music_fluidsynth_mididevice.cpp)\n"
        "else()\n"
        "\ttarget_sources(zmusic-obj INTERFACE\n"
        "\t\tmididevices/music_fluidsynth_stub.cpp)\n"
        "endif()\n",
        "add conditional FluidSynth MIDI source selection",
    )
    replace_once(
        source_cmake,
        "target_link_libraries_hidden(zmusic zmusic-obj adl oplsynth opn timidity timidityplus wildmidi fluidsynth)\n"
        "target_link_libraries_hidden(zmusiclite zmusic-obj fluidsynth)\n",
        "target_link_libraries_hidden(zmusic zmusic-obj adl oplsynth opn timidity timidityplus wildmidi)\n"
        "target_link_libraries_hidden(zmusiclite zmusic-obj)\n"
        "if(ZMUSIC_ENABLE_FLUIDSYNTH)\n"
        "\ttarget_link_libraries_hidden(zmusic fluidsynth)\n"
        "\ttarget_link_libraries_hidden(zmusiclite fluidsynth)\n"
        "endif()\n",
        "make FluidSynth linkage conditional",
    )

    stub_destination = root / "source" / "mididevices" / "music_fluidsynth_stub.cpp"
    shutil.copyfile(stub_source, stub_destination)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
