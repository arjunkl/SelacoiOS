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

    replace_once(
        src_cmake,
        '\tif(NOT MOLTENVK_LIBRARY)\n'
        '\t\tmessage(FATAL_ERROR "MOLTENVK_LIBRARY is required for the iOS target")\n'
        '\tendif()\n'
        '\tset( LINK_FRAMEWORKS "-framework Foundation -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework IOSurface")\n'
        '\ttarget_link_libraries(zdoom ${MOLTENVK_LIBRARY})\n'
        '\tset_target_properties(zdoom PROPERTIES\n'
        '\t\tLINK_FLAGS "${LINK_FRAMEWORKS}"\n'
        '\t\tXCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.runtime.m1"\n'
        '\t\tXCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"\n'
        '\t\tXCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")\n',
        '\tif(NOT MOLTENVK_DYNAMIC_FRAMEWORK)\n'
        '\t\tmessage(FATAL_ERROR "MOLTENVK_DYNAMIC_FRAMEWORK is required for the runtime target")\n'
        '\tendif()\n'
        '\tset(MOLTENVK_DYNAMIC_BINARY "${MOLTENVK_DYNAMIC_FRAMEWORK}/MoltenVK")\n'
        '\tif(NOT EXISTS "${MOLTENVK_DYNAMIC_BINARY}")\n'
        '\t\tmessage(FATAL_ERROR "MoltenVK dynamic framework binary is missing")\n'
        '\tendif()\n'
        '\tset( LINK_FRAMEWORKS "-framework Foundation -framework UIKit -framework QuartzCore -framework Metal -framework CoreGraphics -framework IOSurface")\n'
        '\ttarget_link_libraries(zdoom "${MOLTENVK_DYNAMIC_BINARY}")\n'
        '\tadd_custom_command(TARGET zdoom POST_BUILD\n'
        '\t\tCOMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:zdoom>/Frameworks"\n'
        '\t\tCOMMAND ${CMAKE_COMMAND} -E copy_directory\n'
        '\t\t\t"${MOLTENVK_DYNAMIC_FRAMEWORK}"\n'
        '\t\t\t"$<TARGET_FILE_DIR:zdoom>/Frameworks/MoltenVK.framework")\n'
        '\tset_target_properties(zdoom PROPERTIES\n'
        '\t\tLINK_FLAGS "${LINK_FRAMEWORKS}"\n'
        '\t\tXCODE_ATTRIBUTE_LD_RUNPATH_SEARCH_PATHS "@executable_path/Frameworks"\n'
        '\t\tXCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "am.arjunkl.selacoios.runtime.m1"\n'
        '\t\tXCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"\n'
        '\t\tXCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")\n',
        "switch the runtime target to embedded dynamic MoltenVK",
    )

    replace_once(
        destination,
        '#define VK_USE_PLATFORM_METAL_EXT 1\n#include <vulkan/vulkan.h>\n',
        '#define VK_USE_PLATFORM_METAL_EXT 1\n#include "zvulkan/volk/volk.h"\n',
        "use Volk as the sole Vulkan declaration surface",
    )
    replace_once(
        destination,
        '#include <cstring>\n',
        '#include <cstring>\n#include <dlfcn.h>\n',
        "include the dynamic loader API",
    )
    replace_once(
        destination,
        '    WriteBreadcrumb(@"phase=vulkan_enumerate_instance_extensions");\n'
        '    uint32_t extensionCount = 0;\n',
        '    WriteBreadcrumb(@"phase=vulkan_load_dynamic_moltenvk");\n'
        '    NSString *frameworkBinary = [[[NSBundle mainBundle] bundlePath] '
        'stringByAppendingPathComponent:@"Frameworks/MoltenVK.framework/MoltenVK"];\n'
        '    if (![[NSFileManager defaultManager] fileExistsAtPath:frameworkBinary]) {\n'
        '        output.detail = "embedded MoltenVK.framework binary is missing";\n'
        '        return output;\n'
        '    }\n'
        '    dlerror();\n'
        '    void *moltenVKHandle = dlopen(frameworkBinary.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);\n'
        '    if (moltenVKHandle == nullptr) {\n'
        '        const char *loaderError = dlerror();\n'
        '        output.detail = loaderError != nullptr ? loaderError : "dlopen MoltenVK failed";\n'
        '        return output;\n'
        '    }\n'
        '    auto getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(\n'
        '        dlsym(moltenVKHandle, "vkGetInstanceProcAddr"));\n'
        '    if (getInstanceProcAddr == nullptr) {\n'
        '        output.detail = "dynamic MoltenVK lacks vkGetInstanceProcAddr";\n'
        '        return output;\n'
        '    }\n'
        '    volkInitializeCustom(getInstanceProcAddr);\n'
        '    if (vkEnumerateInstanceExtensionProperties == nullptr || vkCreateInstance == nullptr) {\n'
        '        output.detail = "Volk global dispatch initialization failed";\n'
        '        return output;\n'
        '    }\n'
        '    WriteBreadcrumb(@"phase=vulkan_enumerate_instance_extensions");\n'
        '    uint32_t extensionCount = 0;\n',
        "initialize Volk from the embedded dynamic framework",
    )
    replace_once(
        destination,
        '    WriteBreadcrumb(@"phase=vulkan_instance_created");\n\n'
        '    VkMetalSurfaceCreateInfoEXT surfaceInfo{};\n',
        '    volkLoadInstance(instance);\n'
        '    WriteBreadcrumb(@"phase=vulkan_instance_created_and_dispatch_loaded");\n\n'
        '    VkMetalSurfaceCreateInfoEXT surfaceInfo{};\n',
        "load instance-level Vulkan dispatch",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
