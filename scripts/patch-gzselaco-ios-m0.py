#!/usr/bin/env python3
"""Apply bounded Milestone 0 iOS source-selection edits to pinned GZSelaco."""

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
            "usage: patch-gzselaco-ios-m0.py <GZSelaco source> <iOS overlay platform stub>",
            file=sys.stderr,
        )
        return 2

    root = pathlib.Path(sys.argv[1]).resolve()
    platform_stub = pathlib.Path(sys.argv[2]).resolve()
    overlay_dir = platform_stub.parent
    framebuffer_header = overlay_dir / "gl_sysfb.h"
    framebuffer_source = overlay_dir / "i_framebuffer.cpp"

    if not (root / "CMakeLists.txt").is_file() or not (root / "src" / "CMakeLists.txt").is_file():
        raise RuntimeError(f"not a GZSelaco source checkout: {root}")
    for overlay_file in (platform_stub, framebuffer_header, framebuffer_source):
        if not overlay_file.is_file():
            raise RuntimeError(f"iOS platform overlay is missing: {overlay_file}")

    root_cmake = root / "CMakeLists.txt"
    replace_once(
        root_cmake,
        '\tif( APPLE )\n\t\tset(CMAKE_OSX_DEPLOYMENT_TARGET "10.13")\n',
        '\tif( APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS" )\n'
        '\t\tset(CMAKE_OSX_DEPLOYMENT_TARGET "10.13")\n',
        "guard the desktop Apple deployment target from iOS",
    )
    replace_once(
        root_cmake,
        '\telseif( NOT MINGW )\n'
        '\t\t# Generic GCC/Clang requires position independent executable to be enabled explicitly\n'
        '\t\tset( ALL_C_FLAGS "${ALL_C_FLAGS} -fPIE" )\n'
        '\t\tset( CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -pie" )\n'
        '\tendif( APPLE )\n',
        '\telseif( NOT MINGW )\n'
        '\t\t# Generic GCC/Clang requires position independent executable to be enabled explicitly\n'
        '\t\tset( ALL_C_FLAGS "${ALL_C_FLAGS} -fPIE" )\n'
        '\t\tset( CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -pie" )\n'
        '\tendif()\n',
        "close the broadened Apple condition without stale arguments",
    )
    replace_once(
        root_cmake,
        'add_subdirectory( libraries/discordrpc EXCLUDE_FROM_ALL )\n'
        'set( DRPC_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libraries/discordrpc/include" )\n'
        'set( DRPC_LIBRARIES discord-rpc )\n'
        'set( DRPC_LIBRARY discord-rpc )\n',
        'option(SELACO_DISABLE_DISCORD_RPC "Exclude Discord RPC from this target" OFF)\n'
        'if(SELACO_DISABLE_DISCORD_RPC)\n'
        '\tset(DRPC_INCLUDE_DIR "${CMAKE_BINARY_DIR}/disabled-discordrpc/include")\n'
        '\tfile(MAKE_DIRECTORY "${DRPC_INCLUDE_DIR}")\n'
        '\tset(DRPC_LIBRARIES "")\n'
        '\tset(DRPC_LIBRARY "")\n'
        'else()\n'
        '\tadd_subdirectory( libraries/discordrpc EXCLUDE_FROM_ALL )\n'
        '\tset( DRPC_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/libraries/discordrpc/include" )\n'
        '\tset( DRPC_LIBRARIES discord-rpc )\n'
        '\tset( DRPC_LIBRARY discord-rpc )\n'
        'endif()\n',
        "make Discord RPC explicitly excludable with a valid include path",
    )

    src_cmake = root / "src" / "CMakeLists.txt"
    replace_once(
        src_cmake,
        'add_definitions( -DTHIS_IS_GZDOOM )\n',
        'add_definitions( -DTHIS_IS_GZDOOM )\n'
        'if(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n'
        '\t# CMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY makes the historical\n'
        '\t# function checks appear to find these non-POSIX names. Force the\n'
        '\t# intended aliases for the real device compile.\n'
        '\tadd_definitions(-Dstricmp=strcasecmp -Dstrnicmp=strncasecmp)\n'
        'endif()\n',
        "provide POSIX case-insensitive string aliases on iOS",
    )
    replace_once(
        src_cmake,
        'if( APPLE )\n    option( OSX_COCOA_BACKEND "Use native Cocoa backend instead of SDL" ON )\nendif()\n',
        'if( APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS" )\n'
        '    option( OSX_COCOA_BACKEND "Use native Cocoa backend instead of SDL" ON )\n'
        'endif()\n',
        "prevent the desktop Cocoa backend from becoming the iOS default",
    )
    replace_once(
        src_cmake,
        '\t# Non-Windows version also needs SDL except native OS X backend\n'
        '\tif( NOT APPLE OR NOT OSX_COCOA_BACKEND )\n'
        '\t\tfind_package( SDL2 REQUIRED )\n'
        '\t\tinclude_directories( SYSTEM "${SDL2_INCLUDE_DIR}" )\n'
        '\t\tset( PROJECT_LIBRARIES ${PROJECT_LIBRARIES} "${SDL2_LIBRARY}" )\n'
        '\tendif()\n',
        '\t# iOS owns lifecycle and presentation in the SelacoiOS platform shell.\n'
        '\tif( CMAKE_SYSTEM_NAME STREQUAL "iOS" )\n'
        '\t\tmessage(STATUS "SelacoiOS: desktop SDL backend excluded")\n'
        '\telseif( NOT APPLE OR NOT OSX_COCOA_BACKEND )\n'
        '\t\tfind_package( SDL2 REQUIRED )\n'
        '\t\tinclude_directories( SYSTEM "${SDL2_INCLUDE_DIR}" )\n'
        '\t\tset( PROJECT_LIBRARIES ${PROJECT_LIBRARIES} "${SDL2_LIBRARY}" )\n'
        '\tendif()\n',
        "exclude the desktop SDL backend from iOS",
    )
    replace_once(
        src_cmake,
        'set( PLAT_COCOA_SOURCES\n'
        '\tcommon/platform/posix/cocoa/i_input.mm\n'
        '\tcommon/platform/posix/cocoa/i_joystick.cpp\n'
        '\tcommon/platform/posix/cocoa/i_main.mm\n'
        '\tcommon/platform/posix/cocoa/i_system.mm\n'
        '\tcommon/platform/posix/cocoa/i_video.mm\n'
        '\tcommon/platform/posix/cocoa/st_console.mm\n'
        '\tcommon/platform/posix/cocoa/st_start.mm )\n',
        'set( PLAT_COCOA_SOURCES\n'
        '\tcommon/platform/posix/cocoa/i_input.mm\n'
        '\tcommon/platform/posix/cocoa/i_joystick.cpp\n'
        '\tcommon/platform/posix/cocoa/i_main.mm\n'
        '\tcommon/platform/posix/cocoa/i_system.mm\n'
        '\tcommon/platform/posix/cocoa/i_video.mm\n'
        '\tcommon/platform/posix/cocoa/st_console.mm\n'
        '\tcommon/platform/posix/cocoa/st_start.mm )\n'
        'set( PLAT_IOS_SOURCES\n'
        '\tcommon/platform/ios/i_platform_stub.cpp\n'
        '\tcommon/platform/ios/i_framebuffer.cpp )\n',
        "declare the dedicated iOS platform source set",
    )
    replace_once(
        src_cmake,
        'elseif( APPLE )\n\tif( OSX_COCOA_BACKEND )\n',
        'elseif( CMAKE_SYSTEM_NAME STREQUAL "iOS" )\n'
        '\tmessage(STATUS "SelacoiOS: selected dedicated iOS platform source set")\n'
        '\tset( SYSTEM_SOURCES_DIR common/platform/ios common/platform/posix )\n'
        '\tset( SYSTEM_SOURCES ${PLAT_IOS_SOURCES} )\n'
        '\tset( OTHER_SYSTEM_SOURCES ${PLAT_WIN32_SOURCES} ${PLAT_POSIX_SOURCES} ${PLAT_SDL_SOURCES} ${PLAT_OSX_SOURCES} ${PLAT_COCOA_SOURCES} ${PLAT_UNIX_SOURCES} )\n'
        'elseif( APPLE )\n'
        '\tif( OSX_COCOA_BACKEND )\n',
        "select iOS sources with shared POSIX platform headers",
    )
    replace_once(
        src_cmake,
        'if( APPLE )\n\tset( LINK_FRAMEWORKS "-framework Cocoa -framework IOKit -framework OpenGL")\n',
        'if( CMAKE_SYSTEM_NAME STREQUAL "iOS" )\n'
        '\tif(NOT MOLTENVK_LIBRARY)\n'
        '\t\tmessage(FATAL_ERROR "MOLTENVK_LIBRARY is required for the iOS target")\n'
        '\tendif()\n'
        '\tset( LINK_FRAMEWORKS "-framework Foundation -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework IOSurface")\n'
        '\ttarget_link_libraries(zdoom ${MOLTENVK_LIBRARY})\n'
        '\tset_target_properties(zdoom PROPERTIES\n'
        '\t\tLINK_FLAGS "${LINK_FRAMEWORKS}"\n'
        '\t\tXCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.fullengine.m0"\n'
        '\t\tXCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"\n'
        '\t\tXCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")\n'
        'elseif( APPLE )\n'
        '\tset( LINK_FRAMEWORKS "-framework Cocoa -framework IOKit -framework OpenGL")\n',
        "separate iOS framework linkage from desktop Cocoa",
    )

    zstring_header = root / "src" / "common" / "utility" / "zstring.h"
    replace_once(
        zstring_header,
        '#include <string.h>\n',
        '#include <string.h>\n'
        '#if defined(__APPLE__)\n'
        '#include <strings.h>\n'
        '#endif\n',
        "provide Apple declarations for strcasecmp and strncasecmp",
    )

    zvulkan_cmake = root / "libraries" / "ZVulkan" / "CMakeLists.txt"
    replace_once(
        zvulkan_cmake,
        'option( VULKAN_USE_XLIB "Use Vulkan xlib (X11) WSI integration" ON )\n'
        'option( VULKAN_USE_WAYLAND "Use Vulkan Wayland WSI integration" OFF )\n',
        'option( VULKAN_USE_XLIB "Use Vulkan xlib (X11) WSI integration" ON )\n'
        'option( VULKAN_USE_WAYLAND "Use Vulkan Wayland WSI integration" OFF )\n'
        'if(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n'
        '\tset(VULKAN_USE_XLIB OFF CACHE BOOL "" FORCE)\n'
        '\tset(VULKAN_USE_WAYLAND OFF CACHE BOOL "" FORCE)\n'
        '\tadd_definitions(-DVK_USE_PLATFORM_METAL_EXT=1)\n'
        'endif()\n',
        "disable desktop Vulkan WSI on iOS",
    )
    replace_once(
        zvulkan_cmake,
        'else()\n\tset(ZVULKAN_SOURCES ${ZVULKAN_SOURCES} ${ZVULKAN_UNIX_SOURCES})\n'
        '\tset(ZVULKAN_LIBS ${CMAKE_DL_LIBS} -ldl)\n'
        '\tadd_definitions(-DUNIX -D_UNIX)\n'
        '\tadd_link_options(-pthread)\nendif()\n',
        'elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")\n'
        '\tset(ZVULKAN_SOURCES ${ZVULKAN_SOURCES} ${ZVULKAN_UNIX_SOURCES})\n'
        '\tset(ZVULKAN_LIBS "")\n'
        '\tadd_definitions(-DUNIX -D_UNIX)\n'
        'else()\n'
        '\tset(ZVULKAN_SOURCES ${ZVULKAN_SOURCES} ${ZVULKAN_UNIX_SOURCES})\n'
        '\tset(ZVULKAN_LIBS ${CMAKE_DL_LIBS} -ldl)\n'
        '\tadd_definitions(-DUNIX -D_UNIX)\n'
        '\tadd_link_options(-pthread)\n'
        'endif()\n',
        "remove desktop libdl linkage from iOS ZVulkan",
    )

    richpresence_source = root / "src" / "common" / "thirdparty" / "richpresence.cpp"
    richpresence_source.write_text(
        "// SelacoiOS Milestone 0 null Discord rich-presence backend.\n"
        "// The internal engine API is retained while the desktop Discord RPC\n"
        "// dependency and network-facing integration remain excluded.\n\n"
        "void I_UpdateDiscordPresence(bool, const char*, const char*, const char*)\n"
        "{\n"
        "}\n",
        encoding="utf-8",
    )

    ios_destination = root / "src" / "common" / "platform" / "ios"
    ios_destination.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(platform_stub, ios_destination / "i_platform_stub.cpp")
    shutil.copyfile(framebuffer_header, ios_destination / "gl_sysfb.h")
    shutil.copyfile(framebuffer_source, ios_destination / "i_framebuffer.cpp")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
