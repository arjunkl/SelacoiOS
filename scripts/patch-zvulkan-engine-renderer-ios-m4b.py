#!/usr/bin/env python3
"""Use embedded MoltenVK for GZSelaco and record the first engine present."""

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
        print("usage: patch-zvulkan-engine-renderer-ios-m4b.py <GZSelaco source>", file=sys.stderr)
        return 2
    root = pathlib.Path(sys.argv[1]).resolve()
    zvulkan_cmake = root / "libraries" / "ZVulkan" / "CMakeLists.txt"
    instance = root / "libraries" / "ZVulkan" / "src" / "vulkaninstance.cpp"
    swapchain = root / "libraries" / "ZVulkan" / "src" / "vulkanswapchain.cpp"
    for path in (zvulkan_cmake, instance, swapchain):
        if not path.is_file():
            raise RuntimeError(f"Milestone 4B ZVulkan prerequisite is missing: {path}")

    replace_once(
        zvulkan_cmake,
        "add_library(zvulkan STATIC ${ZVULKAN_SOURCES} ${ZVULKAN_INCLUDES} ${VULKAN_INCLUDES})\n"
        "target_link_libraries(zvulkan ${ZVULKAN_LIBS})\n",
        "add_library(zvulkan STATIC ${ZVULKAN_SOURCES} ${ZVULKAN_INCLUDES} ${VULKAN_INCLUDES})\n"
        "if(CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "\ttarget_compile_definitions(zvulkan PRIVATE SELACO_IOS_ENGINE_RENDERER_HANDOFF=1)\n"
        "endif()\n"
        "target_link_libraries(zvulkan ${ZVULKAN_LIBS})\n",
        "compile the ZVulkan library with the embedded MoltenVK loader path",
    )

    replace_once(
        instance,
        '#include <cstring>\n\nVulkanInstance::VulkanInstance(',
        '#include <cstring>\n\n'
        '#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)\n'
        'extern "C" PFN_vkGetInstanceProcAddr SelacoIOSGetVkGetInstanceProcAddr();\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n'
        '#endif\n\nVulkanInstance::VulkanInstance(',
        "declare the embedded MoltenVK loader bridge",
    )
    replace_once(
        instance,
        """void VulkanInstance::InitVolk()
{
\tif (volkInitialize() != VK_SUCCESS)
\t{
\t\tVulkanError("Unable to find Vulkan");
\t}
\tauto iver = volkGetInstanceVersion();
""",
        """void VulkanInstance::InitVolk()
{
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\tauto getInstanceProcAddr = SelacoIOSGetVkGetInstanceProcAddr();
\tif (getInstanceProcAddr == nullptr)
\t{
\t\tVulkanError("Unable to resolve embedded MoltenVK loader");
\t}
\tvolkInitializeCustom(getInstanceProcAddr);
\tSelacoIOSReportLicensedAssetProbe("engine_volk_dispatch_ready", "ZVulkan target used volkInitializeCustom with embedded MoltenVK");
#else
\tif (volkInitialize() != VK_SUCCESS)
\t{
\t\tVulkanError("Unable to find Vulkan");
\t}
#endif
\tauto iver = volkGetInstanceVersion();
""",
        "initialize Volk from embedded MoltenVK",
    )
    replace_once(
        instance,
        """\t\tcreateInfo.ppEnabledLayerNames = enabledValidationLayersCStr.data();
\t\tcreateInfo.ppEnabledExtensionNames = enabledExtensionsCStr.data();

\t\tresult = vkCreateInstance(&createInfo, nullptr, &Instance);
""",
        """\t\tcreateInfo.ppEnabledLayerNames = enabledValidationLayersCStr.data();
\t\tcreateInfo.ppEnabledExtensionNames = enabledExtensionsCStr.data();
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\t\tif (EnabledExtensions.find(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) != EnabledExtensions.end())
\t\t{
\t\t\tcreateInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
\t\t}
#endif

\t\tresult = vkCreateInstance(&createInfo, nullptr, &Instance);
""",
        "enable MoltenVK portability enumeration",
    )
    replace_once(
        instance,
        '\tvolkLoadInstance(Instance);\n\n\tif (debugLayerFound)\n',
        '\tvolkLoadInstance(Instance);\n'
        '#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)\n'
        '\tSelacoIOSReportLicensedAssetProbe("engine_instance_dispatch_ready", "volkLoadInstance completed");\n'
        '#endif\n\n\tif (debugLayerFound)\n',
        "record instance dispatch initialization",
    )

    replace_once(
        swapchain,
        '#include "vulkanbuilders.h"\n\nVulkanSwapChain::VulkanSwapChain',
        '#include "vulkanbuilders.h"\n\n'
        '#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)\n'
        'extern "C" void SelacoIOSReportLicensedAssetProbe(const char *phase, const char *detail);\n'
        '#endif\n\nVulkanSwapChain::VulkanSwapChain',
        "declare first-present reporting",
    )
    replace_once(
        swapchain,
        """\tif (result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR)
\t{
\t\treturn;
\t}
""",
        """\tif (result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR)
\t{
#if defined(SELACO_IOS_ENGINE_RENDERER_HANDOFF)
\t\tstatic bool reportedFirstPresent = false;
\t\tif (!reportedFirstPresent)
\t\t{
\t\t\treportedFirstPresent = true;
\t\t\tSelacoIOSReportLicensedAssetProbe(
\t\t\t\t"engine_first_frame_presented",
\t\t\t\t"GZSelaco Vulkan swapchain presented successfully");
\t\t}
#endif
\t\treturn;
\t}
""",
        "record the first engine-owned present",
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
