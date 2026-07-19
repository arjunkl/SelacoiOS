#include "SelacoVulkanBoundary.h"

#include <vulkan/vulkan.h>

#include <cstring>
#include <vector>

unsigned int SelacoIOSVulkanCompiledVersion(void)
{
    return VK_HEADER_VERSION_COMPLETE;
}

int SelacoIOSVulkanSelfTest(void)
{
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

    bool has_portability_enumeration = false;
    for (const VkExtensionProperties &extension : extensions) {
        if (std::strcmp(extension.extensionName, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME) == 0) {
            has_portability_enumeration = true;
            break;
        }
    }

    const char *enabled_extensions[] = {
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };

    VkApplicationInfo application_info{};
    application_info.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    application_info.pApplicationName = "SelacoiOS Milestone 0";
    application_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 0, 1);
    application_info.pEngineName = "GZSelaco iOS boundary";
    application_info.engineVersion = VK_MAKE_API_VERSION(0, 4, 13, 0);
    application_info.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo create_info{};
    create_info.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create_info.pApplicationInfo = &application_info;
    if (has_portability_enumeration) {
        create_info.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        create_info.enabledExtensionCount = 1;
        create_info.ppEnabledExtensionNames = enabled_extensions;
    }

    VkInstance instance = VK_NULL_HANDLE;
    result = vkCreateInstance(&create_info, nullptr, &instance);
    if (result != VK_SUCCESS) {
        return static_cast<int>(result);
    }

    vkDestroyInstance(instance, nullptr);
    return 1;
}
