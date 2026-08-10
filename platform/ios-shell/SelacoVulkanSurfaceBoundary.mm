#import <QuartzCore/CAMetalLayer.h>

#define VK_USE_PLATFORM_METAL_EXT 1
#include <vulkan/vulkan.h>

#include "SelacoVulkanBoundary.h"

#include <cstring>
#include <vector>

int SelacoIOSVulkanSurfaceSelfTest(void *metal_layer)
{
    CAMetalLayer *layer = (__bridge CAMetalLayer *)metal_layer;
    if (layer == nil) {
        return static_cast<int>(VK_ERROR_INITIALIZATION_FAILED);
    }

    uint32_t extension_count = 0;
    VkResult result = vkEnumerateInstanceExtensionProperties(nullptr, &extension_count, nullptr);
    if (result != VK_SUCCESS) {
        return static_cast<int>(result);
    }

    std::vector<VkExtensionProperties> extensions(extension_count);
    if (extension_count > 0) {
        result = vkEnumerateInstanceExtensionProperties(nullptr, &extension_count, extensions.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            return static_cast<int>(result);
        }
    }

    const auto has_extension = [&extensions](const char *required_name) {
        for (const VkExtensionProperties &extension : extensions) {
            if (std::strcmp(extension.extensionName, required_name) == 0) {
                return true;
            }
        }
        return false;
    };

    if (!has_extension(VK_KHR_SURFACE_EXTENSION_NAME) ||
        !has_extension(VK_EXT_METAL_SURFACE_EXTENSION_NAME)) {
        return static_cast<int>(VK_ERROR_EXTENSION_NOT_PRESENT);
    }

    const bool has_portability_enumeration =
        has_extension(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);

    const char *enabled_extensions[3] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };

    VkApplicationInfo application_info{};
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application_info.pApplicationName = "SelacoiOS Metal surface boundary";
    application_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 0, 1);
    application_info.pEngineName = "GZSelaco iOS boundary";
    application_info.engineVersion = VK_MAKE_API_VERSION(0, 4, 13, 0);
    application_info.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo instance_info{};
    instance_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instance_info.pApplicationInfo = &application_info;
    instance_info.enabledExtensionCount = has_portability_enumeration ? 3U : 2U;
    instance_info.ppEnabledExtensionNames = enabled_extensions;
    if (has_portability_enumeration) {
        instance_info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    VkInstance instance = VK_NULL_HANDLE;
    result = vkCreateInstance(&instance_info, nullptr, &instance);
    if (result != VK_SUCCESS) {
        return static_cast<int>(result);
    }

    VkMetalSurfaceCreateInfoEXT surface_info{};
    surface_info.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surface_info.pLayer = layer;

    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = vkCreateMetalSurfaceEXT(instance, &surface_info, nullptr, &surface);
    if (result == VK_SUCCESS) {
        vkDestroySurfaceKHR(instance, surface, nullptr);
    }

    vkDestroyInstance(instance, nullptr);
    return result == VK_SUCCESS ? 1 : static_cast<int>(result);
}
