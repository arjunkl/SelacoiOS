// SelacoiOS Milestone 2 physical-device swapchain clear-frame probe.
//
// UIKit owns the lifecycle and a CAMetalLayer. The bounded Vulkan path loads
// the embedded dynamic MoltenVK framework through Volk, creates a logical
// device and FIFO swapchain, records render-pass clear commands, and presents
// continuously. It does not load Selaco.ipk3 or enter the GZSelaco game loop.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#define VK_USE_PLATFORM_METAL_EXT 1
#define VK_NO_PROTOTYPES 1
#include "zvulkan/volk/volk.h"

#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include <dlfcn.h>
#include <limits>
#include <mach/mach_time.h>
#include <memory>
#include <string>
#include <vector>

#include "cmdlib.h"
#include "i_system.h"
#include "i_video.h"
#include "m_argv.h"
#include "tarray.h"
#include "zstring.h"

class FGameTexture;

extern "C" void SelacoIOSSetDrawableSize(int width, int height);

FArgs *Args = nullptr;
IVideo *Video = nullptr;

double PerfToSec = 1.0e-9;
double PerfToMillisec = 1.0e-6;

namespace {
constexpr const char *kSwapchainExtension = "VK_KHR_swapchain";
constexpr const char *kPortabilitySubsetExtension = "VK_KHR_portability_subset";
constexpr uint64_t kFenceTimeoutNanoseconds = 2'000'000'000ULL;

NSString *DiagnosticDirectory()
{
    NSString *documents = NSSearchPathForDirectoriesInDomains(
        NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (documents.length == 0) {
        return nil;
    }

    NSString *directory = [documents stringByAppendingPathComponent:@"Selaco"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    return directory;
}

NSString *DiagnosticPath(NSString *filename)
{
    NSString *directory = DiagnosticDirectory();
    return directory == nil ? nil : [directory stringByAppendingPathComponent:filename];
}

void WriteBreadcrumb(NSString *phase)
{
    if (phase == nil) {
        return;
    }

    NSString *path = DiagnosticPath(@"runtime-bootstrap.txt");
    if (path != nil) {
        NSString *existing = [NSString stringWithContentsOfFile:path
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (existing == nil) {
            existing = @"SelacoiOS Milestone 2 swapchain log\n";
        }
        NSString *updated = [existing stringByAppendingFormat:@"%@\n", phase];
        [updated writeToFile:path
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
    }

    std::fprintf(stderr, "SelacoiOS phase: %s\n", phase.UTF8String);
    std::fflush(stderr);
}

void WriteStatusSnapshot(NSString *text)
{
    if (text == nil) {
        return;
    }
    NSString *path = DiagnosticPath(@"swapchain-status.txt");
    if (path != nil) {
        [text writeToFile:path
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:nil];
    }
}

FString PathForDirectory(NSSearchPathDirectory directory, const char *leaf, bool create)
{
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(
        directory, NSUserDomainMask, YES);
    if (paths.count == 0) {
        return FString();
    }

    NSString *path = paths.firstObject;
    if (leaf != nullptr && leaf[0] != '\0') {
        path = [path stringByAppendingPathComponent:
            [NSString stringWithUTF8String:leaf]];
    }

    if (create) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return path.fileSystemRepresentation;
}

FString AppSupportPath(bool create)
{
    return PathForDirectory(NSApplicationSupportDirectory, "Selaco", create);
}

FString DocumentsPath(const char *leaf, bool create)
{
    FString root = PathForDirectory(NSDocumentDirectory, "Selaco", create);
    if (root.IsEmpty() || leaf == nullptr || leaf[0] == '\0') {
        return root;
    }

    NSString *rootString = [NSString stringWithUTF8String:root.GetChars()];
    NSString *path = [rootString stringByAppendingPathComponent:
        [NSString stringWithUTF8String:leaf]];
    if (create) {
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return path.fileSystemRepresentation;
}

bool HasNamedExtension(const std::vector<VkExtensionProperties>& extensions, const char *name)
{
    for (const VkExtensionProperties& extension : extensions) {
        if (std::strcmp(extension.extensionName, name) == 0) {
            return true;
        }
    }
    return false;
}

const char *FormatName(VkFormat format)
{
    switch (format) {
    case VK_FORMAT_B8G8R8A8_UNORM:
        return "BGRA8 UNORM";
    case VK_FORMAT_B8G8R8A8_SRGB:
        return "BGRA8 SRGB";
    case VK_FORMAT_R8G8B8A8_UNORM:
        return "RGBA8 UNORM";
    case VK_FORMAT_R8G8B8A8_SRGB:
        return "RGBA8 SRGB";
    default:
        return "other";
    }
}

struct SwapchainStatus
{
    bool initialized = false;
    bool presenting = false;
    int resultCode = static_cast<int>(VK_ERROR_INITIALIZATION_FAILED);
    std::string detail = "not initialized";
    std::string deviceName = "not enumerated";
    std::string formatName = "n/a";
    std::string presentModeName = "FIFO";
    uint32_t queueFamily = UINT32_MAX;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t imageCount = 0;
    uint64_t framesPresented = 0;
};

class VulkanSwapchainPresenter
{
public:
    explicit VulkanSwapchainPresenter(CAMetalLayer *layer)
        : layer_(layer)
    {
    }

    ~VulkanSwapchainPresenter()
    {
        DestroyAll();
    }

    const SwapchainStatus& Status() const
    {
        return status_;
    }

    bool Initialize()
    {
        WriteBreadcrumb(@"phase=m2_initialize_entered");
        if (layer_ == nil || layer_.device == nil) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED, "CAMetalLayer or Metal device unavailable");
        }
        if (!LoadDynamicMoltenVK()) {
            return false;
        }
        if (!CreateInstanceAndSurface()) {
            return false;
        }
        if (!SelectPhysicalDeviceAndQueue()) {
            return false;
        }
        if (!CreateLogicalDevice()) {
            return false;
        }
        if (!CreateSwapchainResources()) {
            return false;
        }

        status_.initialized = true;
        status_.presenting = true;
        status_.resultCode = static_cast<int>(VK_SUCCESS);
        status_.detail = "logical device, FIFO swapchain, clear render pass, and presentation resources ready";
        WriteBreadcrumb(@"phase=m2_swapchain_initialized");
        return true;
    }

    VkResult DrawFrame()
    {
        if (!status_.initialized || paused_) {
            return VK_NOT_READY;
        }

        const CGSize drawableSize = layer_.drawableSize;
        const uint32_t drawableWidth = std::max(1U, static_cast<uint32_t>(drawableSize.width));
        const uint32_t drawableHeight = std::max(1U, static_cast<uint32_t>(drawableSize.height));
        if (drawableWidth != extent_.width || drawableHeight != extent_.height) {
            recreateRequested_ = true;
        }

        if (recreateRequested_) {
            if (!CreateSwapchainResources()) {
                status_.presenting = false;
                return static_cast<VkResult>(status_.resultCode);
            }
        }

        VkResult result = vkWaitForFences(
            device_, 1, &inFlightFence_, VK_TRUE, kFenceTimeoutNanoseconds);
        if (result != VK_SUCCESS) {
            Fail(result, "vkWaitForFences failed");
            return result;
        }

        uint32_t imageIndex = 0;
        result = vkAcquireNextImageKHR(
            device_, swapchain_, UINT64_MAX, imageAvailable_, VK_NULL_HANDLE, &imageIndex);
        if (result == VK_ERROR_OUT_OF_DATE_KHR) {
            recreateRequested_ = true;
            return result;
        }
        const bool suboptimalAcquire = result == VK_SUBOPTIMAL_KHR;
        if (result != VK_SUCCESS && !suboptimalAcquire) {
            Fail(result, "vkAcquireNextImageKHR failed");
            return result;
        }

        result = vkResetFences(device_, 1, &inFlightFence_);
        if (result != VK_SUCCESS) {
            Fail(result, "vkResetFences failed");
            return result;
        }

        VkPipelineStageFlags waitStage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        VkSubmitInfo submitInfo{};
        submitInfo.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
        submitInfo.waitSemaphoreCount = 1;
        submitInfo.pWaitSemaphores = &imageAvailable_;
        submitInfo.pWaitDstStageMask = &waitStage;
        submitInfo.commandBufferCount = 1;
        submitInfo.pCommandBuffers = &commandBuffers_[imageIndex];
        submitInfo.signalSemaphoreCount = 1;
        submitInfo.pSignalSemaphores = &renderFinished_;

        result = vkQueueSubmit(queue_, 1, &submitInfo, inFlightFence_);
        if (result != VK_SUCCESS) {
            Fail(result, "vkQueueSubmit failed");
            return result;
        }

        VkPresentInfoKHR presentInfo{};
        presentInfo.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR;
        presentInfo.waitSemaphoreCount = 1;
        presentInfo.pWaitSemaphores = &renderFinished_;
        presentInfo.swapchainCount = 1;
        presentInfo.pSwapchains = &swapchain_;
        presentInfo.pImageIndices = &imageIndex;

        result = vkQueuePresentKHR(queue_, &presentInfo);
        if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR || suboptimalAcquire) {
            recreateRequested_ = true;
        } else if (result != VK_SUCCESS) {
            Fail(result, "vkQueuePresentKHR failed");
            return result;
        }

        status_.framesPresented += 1;
        status_.resultCode = static_cast<int>(result == VK_SUBOPTIMAL_KHR ? VK_SUCCESS : result);
        status_.presenting = true;
        if (status_.framesPresented == 1) {
            WriteBreadcrumb(@"phase=m2_first_frame_presented");
        } else if (status_.framesPresented == 300) {
            WriteBreadcrumb(@"phase=m2_300_frames_presented");
        }
        return result;
    }

    void Pause()
    {
        paused_ = true;
        status_.presenting = false;
        if (device_ != VK_NULL_HANDLE) {
            vkDeviceWaitIdle(device_);
        }
        WriteBreadcrumb(@"phase=m2_presenter_paused");
    }

    void Resume()
    {
        paused_ = false;
        recreateRequested_ = true;
        status_.presenting = status_.initialized;
        WriteBreadcrumb(@"phase=m2_presenter_resumed");
    }

    void RequestRecreate()
    {
        recreateRequested_ = true;
    }

private:
    bool Fail(VkResult result, const char *detail)
    {
        status_.resultCode = static_cast<int>(result);
        status_.detail = detail == nullptr ? "unknown failure" : detail;
        status_.presenting = false;
        NSString *message = [NSString stringWithFormat:@"phase=m2_failure code=%d detail=%s",
            static_cast<int>(result), status_.detail.c_str()];
        WriteBreadcrumb(message);
        return false;
    }

    bool LoadDynamicMoltenVK()
    {
        WriteBreadcrumb(@"phase=m2_load_dynamic_moltenvk");
        NSString *frameworkBinary = [[NSBundle mainBundle]
            pathForResource:@"MoltenVK"
                     ofType:nil
                inDirectory:@"Frameworks/MoltenVK.framework"];
        if (frameworkBinary == nil) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED, "embedded MoltenVK.framework binary missing");
        }

        moltenVKHandle_ = dlopen(frameworkBinary.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (moltenVKHandle_ == nullptr) {
            const char *error = dlerror();
            return Fail(VK_ERROR_INITIALIZATION_FAILED,
                error == nullptr ? "dlopen MoltenVK failed" : error);
        }

        auto getInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(
            dlsym(moltenVKHandle_, "vkGetInstanceProcAddr"));
        if (getInstanceProcAddr == nullptr) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED,
                "dynamic MoltenVK lacks vkGetInstanceProcAddr");
        }

        volkInitializeCustom(getInstanceProcAddr);
        if (vkEnumerateInstanceExtensionProperties == nullptr || vkCreateInstance == nullptr) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED, "Volk global dispatch initialization failed");
        }
        WriteBreadcrumb(@"phase=m2_volk_global_dispatch_ready");
        return true;
    }

    bool CreateInstanceAndSurface()
    {
        uint32_t extensionCount = 0;
        VkResult result = vkEnumerateInstanceExtensionProperties(
            nullptr, &extensionCount, nullptr);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkEnumerateInstanceExtensionProperties(count) failed");
        }
        std::vector<VkExtensionProperties> extensions(extensionCount);
        result = vkEnumerateInstanceExtensionProperties(
            nullptr, &extensionCount, extensions.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            return Fail(result, "vkEnumerateInstanceExtensionProperties(list) failed");
        }
        if (!HasNamedExtension(extensions, VK_KHR_SURFACE_EXTENSION_NAME) ||
            !HasNamedExtension(extensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME)) {
            return Fail(VK_ERROR_EXTENSION_NOT_PRESENT,
                "VK_KHR_surface or VK_EXT_metal_surface unavailable");
        }

        const bool portability = HasNamedExtension(
            extensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        std::array<const char *, 3> enabledExtensions = {
            VK_KHR_SURFACE_EXTENSION_NAME,
            VK_EXT_METAL_SURFACE_EXTENSION_NAME,
            VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
        };

        VkApplicationInfo appInfo{};
        appInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
        appInfo.pApplicationName = "SelacoiOS Swapchain Probe";
        appInfo.applicationVersion = VK_MAKE_API_VERSION(0, 0, 4, 0);
        appInfo.pEngineName = "GZSelaco iOS Runtime Boundary";
        appInfo.engineVersion = VK_MAKE_API_VERSION(0, 4, 13, 0);
        appInfo.apiVersion = VK_API_VERSION_1_1;

        VkInstanceCreateInfo createInfo{};
        createInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
        createInfo.pApplicationInfo = &appInfo;
        createInfo.enabledExtensionCount = portability ? 3U : 2U;
        createInfo.ppEnabledExtensionNames = enabledExtensions.data();
        if (portability) {
            createInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
        }

        result = vkCreateInstance(&createInfo, nullptr, &instance_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateInstance failed");
        }
        volkLoadInstance(instance_);
        WriteBreadcrumb(@"phase=m2_instance_dispatch_ready");

        VkMetalSurfaceCreateInfoEXT surfaceInfo{};
        surfaceInfo.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
        surfaceInfo.pLayer = layer_;
        result = vkCreateMetalSurfaceEXT(instance_, &surfaceInfo, nullptr, &surface_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateMetalSurfaceEXT failed");
        }
        WriteBreadcrumb(@"phase=m2_metal_surface_created");
        return true;
    }

    bool SelectPhysicalDeviceAndQueue()
    {
        uint32_t deviceCount = 0;
        VkResult result = vkEnumeratePhysicalDevices(instance_, &deviceCount, nullptr);
        if (result != VK_SUCCESS || deviceCount == 0) {
            return Fail(result == VK_SUCCESS ? VK_ERROR_INITIALIZATION_FAILED : result,
                "no Vulkan physical device enumerated");
        }
        std::vector<VkPhysicalDevice> devices(deviceCount);
        result = vkEnumeratePhysicalDevices(instance_, &deviceCount, devices.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            return Fail(result, "vkEnumeratePhysicalDevices(list) failed");
        }

        for (VkPhysicalDevice candidate : devices) {
            uint32_t extensionCount = 0;
            vkEnumerateDeviceExtensionProperties(candidate, nullptr, &extensionCount, nullptr);
            std::vector<VkExtensionProperties> deviceExtensions(extensionCount);
            vkEnumerateDeviceExtensionProperties(
                candidate, nullptr, &extensionCount, deviceExtensions.data());
            if (!HasNamedExtension(deviceExtensions, kSwapchainExtension)) {
                continue;
            }

            uint32_t queueCount = 0;
            vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queueCount, nullptr);
            std::vector<VkQueueFamilyProperties> queues(queueCount);
            vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queueCount, queues.data());

            for (uint32_t index = 0; index < queueCount; ++index) {
                if ((queues[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 0) {
                    continue;
                }
                VkBool32 presentSupported = VK_FALSE;
                result = vkGetPhysicalDeviceSurfaceSupportKHR(
                    candidate, index, surface_, &presentSupported);
                if (result == VK_SUCCESS && presentSupported == VK_TRUE) {
                    physicalDevice_ = candidate;
                    queueFamily_ = index;
                    portabilitySubset_ = HasNamedExtension(
                        deviceExtensions, kPortabilitySubsetExtension);
                    VkPhysicalDeviceProperties properties{};
                    vkGetPhysicalDeviceProperties(candidate, &properties);
                    status_.deviceName = properties.deviceName;
                    status_.queueFamily = index;
                    WriteBreadcrumb(@"phase=m2_physical_device_and_queue_selected");
                    return true;
                }
            }
        }
        return Fail(VK_ERROR_FEATURE_NOT_PRESENT,
            "no graphics queue with swapchain presentation support");
    }

    bool CreateLogicalDevice()
    {
        const float priority = 1.0f;
        VkDeviceQueueCreateInfo queueInfo{};
        queueInfo.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
        queueInfo.queueFamilyIndex = queueFamily_;
        queueInfo.queueCount = 1;
        queueInfo.pQueuePriorities = &priority;

        std::array<const char *, 2> extensions = {
            kSwapchainExtension,
            kPortabilitySubsetExtension,
        };
        VkDeviceCreateInfo createInfo{};
        createInfo.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
        createInfo.queueCreateInfoCount = 1;
        createInfo.pQueueCreateInfos = &queueInfo;
        createInfo.enabledExtensionCount = portabilitySubset_ ? 2U : 1U;
        createInfo.ppEnabledExtensionNames = extensions.data();

        VkResult result = vkCreateDevice(physicalDevice_, &createInfo, nullptr, &device_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateDevice failed");
        }
        volkLoadDevice(device_);
        vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);
        if (queue_ == VK_NULL_HANDLE) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED, "vkGetDeviceQueue returned null");
        }
        WriteBreadcrumb(@"phase=m2_logical_device_ready");
        return true;
    }

    VkSurfaceFormatKHR ChooseSurfaceFormat(const std::vector<VkSurfaceFormatKHR>& formats)
    {
        if (formats.size() == 1 && formats[0].format == VK_FORMAT_UNDEFINED) {
            return {VK_FORMAT_B8G8R8A8_UNORM, VK_COLOR_SPACE_SRGB_NONLINEAR_KHR};
        }
        for (const VkSurfaceFormatKHR& format : formats) {
            if (format.format == VK_FORMAT_B8G8R8A8_UNORM &&
                format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return format;
            }
        }
        for (const VkSurfaceFormatKHR& format : formats) {
            if (format.format == VK_FORMAT_B8G8R8A8_SRGB &&
                format.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) {
                return format;
            }
        }
        return formats.front();
    }

    VkExtent2D ChooseExtent(const VkSurfaceCapabilitiesKHR& capabilities)
    {
        if (capabilities.currentExtent.width != std::numeric_limits<uint32_t>::max()) {
            return capabilities.currentExtent;
        }
        const CGSize drawableSize = layer_.drawableSize;
        VkExtent2D extent{
            std::max(1U, static_cast<uint32_t>(drawableSize.width)),
            std::max(1U, static_cast<uint32_t>(drawableSize.height)),
        };
        extent.width = std::min(
            std::max(extent.width, capabilities.minImageExtent.width),
            capabilities.maxImageExtent.width);
        extent.height = std::min(
            std::max(extent.height, capabilities.minImageExtent.height),
            capabilities.maxImageExtent.height);
        return extent;
    }

    VkCompositeAlphaFlagBitsKHR ChooseCompositeAlpha(
        const VkSurfaceCapabilitiesKHR& capabilities)
    {
        const std::array<VkCompositeAlphaFlagBitsKHR, 4> choices = {
            VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
            VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
            VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
        };
        for (VkCompositeAlphaFlagBitsKHR choice : choices) {
            if ((capabilities.supportedCompositeAlpha & choice) != 0) {
                return choice;
            }
        }
        return VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    }

    bool CreateSwapchainResources()
    {
        if (device_ == VK_NULL_HANDLE || surface_ == VK_NULL_HANDLE) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED,
                "device or surface missing before swapchain creation");
        }
        vkDeviceWaitIdle(device_);
        DestroySwapchainResources();

        VkSurfaceCapabilitiesKHR capabilities{};
        VkResult result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(
            physicalDevice_, surface_, &capabilities);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed");
        }
        if ((capabilities.supportedUsageFlags & VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT) == 0) {
            return Fail(VK_ERROR_FORMAT_NOT_SUPPORTED,
                "surface images do not support color attachments");
        }

        uint32_t formatCount = 0;
        result = vkGetPhysicalDeviceSurfaceFormatsKHR(
            physicalDevice_, surface_, &formatCount, nullptr);
        if (result != VK_SUCCESS || formatCount == 0) {
            return Fail(result == VK_SUCCESS ? VK_ERROR_FORMAT_NOT_SUPPORTED : result,
                "no surface formats available");
        }
        std::vector<VkSurfaceFormatKHR> formats(formatCount);
        result = vkGetPhysicalDeviceSurfaceFormatsKHR(
            physicalDevice_, surface_, &formatCount, formats.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            return Fail(result, "vkGetPhysicalDeviceSurfaceFormatsKHR(list) failed");
        }

        uint32_t presentModeCount = 0;
        result = vkGetPhysicalDeviceSurfacePresentModesKHR(
            physicalDevice_, surface_, &presentModeCount, nullptr);
        if (result != VK_SUCCESS || presentModeCount == 0) {
            return Fail(result == VK_SUCCESS ? VK_ERROR_INITIALIZATION_FAILED : result,
                "no surface present modes available");
        }
        std::vector<VkPresentModeKHR> presentModes(presentModeCount);
        result = vkGetPhysicalDeviceSurfacePresentModesKHR(
            physicalDevice_, surface_, &presentModeCount, presentModes.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            return Fail(result, "vkGetPhysicalDeviceSurfacePresentModesKHR(list) failed");
        }
        if (std::find(presentModes.begin(), presentModes.end(), VK_PRESENT_MODE_FIFO_KHR) ==
            presentModes.end()) {
            return Fail(VK_ERROR_INITIALIZATION_FAILED, "FIFO present mode unavailable");
        }

        surfaceFormat_ = ChooseSurfaceFormat(formats);
        extent_ = ChooseExtent(capabilities);
        uint32_t imageCount = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount > 0 && imageCount > capabilities.maxImageCount) {
            imageCount = capabilities.maxImageCount;
        }

        VkSwapchainCreateInfoKHR createInfo{};
        createInfo.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR;
        createInfo.surface = surface_;
        createInfo.minImageCount = imageCount;
        createInfo.imageFormat = surfaceFormat_.format;
        createInfo.imageColorSpace = surfaceFormat_.colorSpace;
        createInfo.imageExtent = extent_;
        createInfo.imageArrayLayers = 1;
        createInfo.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        createInfo.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        createInfo.preTransform = capabilities.currentTransform;
        createInfo.compositeAlpha = ChooseCompositeAlpha(capabilities);
        createInfo.presentMode = VK_PRESENT_MODE_FIFO_KHR;
        createInfo.clipped = VK_TRUE;
        createInfo.oldSwapchain = VK_NULL_HANDLE;

        result = vkCreateSwapchainKHR(device_, &createInfo, nullptr, &swapchain_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateSwapchainKHR failed");
        }

        uint32_t actualImageCount = 0;
        result = vkGetSwapchainImagesKHR(device_, swapchain_, &actualImageCount, nullptr);
        if (result != VK_SUCCESS || actualImageCount == 0) {
            return Fail(result == VK_SUCCESS ? VK_ERROR_INITIALIZATION_FAILED : result,
                "vkGetSwapchainImagesKHR(count) failed");
        }
        images_.resize(actualImageCount);
        result = vkGetSwapchainImagesKHR(
            device_, swapchain_, &actualImageCount, images_.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            return Fail(result, "vkGetSwapchainImagesKHR(list) failed");
        }

        imageViews_.resize(images_.size(), VK_NULL_HANDLE);
        for (size_t index = 0; index < images_.size(); ++index) {
            VkImageViewCreateInfo viewInfo{};
            viewInfo.sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO;
            viewInfo.image = images_[index];
            viewInfo.viewType = VK_IMAGE_VIEW_TYPE_2D;
            viewInfo.format = surfaceFormat_.format;
            viewInfo.components = {
                VK_COMPONENT_SWIZZLE_IDENTITY,
                VK_COMPONENT_SWIZZLE_IDENTITY,
                VK_COMPONENT_SWIZZLE_IDENTITY,
                VK_COMPONENT_SWIZZLE_IDENTITY,
            };
            viewInfo.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            viewInfo.subresourceRange.baseMipLevel = 0;
            viewInfo.subresourceRange.levelCount = 1;
            viewInfo.subresourceRange.baseArrayLayer = 0;
            viewInfo.subresourceRange.layerCount = 1;
            result = vkCreateImageView(device_, &viewInfo, nullptr, &imageViews_[index]);
            if (result != VK_SUCCESS) {
                return Fail(result, "vkCreateImageView failed");
            }
        }

        VkAttachmentDescription colorAttachment{};
        colorAttachment.format = surfaceFormat_.format;
        colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
        colorAttachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        VkAttachmentReference colorReference{};
        colorReference.attachment = 0;
        colorReference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        VkSubpassDescription subpass{};
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpass.colorAttachmentCount = 1;
        subpass.pColorAttachments = &colorReference;

        VkSubpassDependency dependency{};
        dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
        dependency.dstSubpass = 0;
        dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

        VkRenderPassCreateInfo renderPassInfo{};
        renderPassInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO;
        renderPassInfo.attachmentCount = 1;
        renderPassInfo.pAttachments = &colorAttachment;
        renderPassInfo.subpassCount = 1;
        renderPassInfo.pSubpasses = &subpass;
        renderPassInfo.dependencyCount = 1;
        renderPassInfo.pDependencies = &dependency;
        result = vkCreateRenderPass(device_, &renderPassInfo, nullptr, &renderPass_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateRenderPass failed");
        }

        framebuffers_.resize(imageViews_.size(), VK_NULL_HANDLE);
        for (size_t index = 0; index < imageViews_.size(); ++index) {
            VkFramebufferCreateInfo framebufferInfo{};
            framebufferInfo.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
            framebufferInfo.renderPass = renderPass_;
            framebufferInfo.attachmentCount = 1;
            framebufferInfo.pAttachments = &imageViews_[index];
            framebufferInfo.width = extent_.width;
            framebufferInfo.height = extent_.height;
            framebufferInfo.layers = 1;
            result = vkCreateFramebuffer(
                device_, &framebufferInfo, nullptr, &framebuffers_[index]);
            if (result != VK_SUCCESS) {
                return Fail(result, "vkCreateFramebuffer failed");
            }
        }

        VkCommandPoolCreateInfo poolInfo{};
        poolInfo.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
        poolInfo.queueFamilyIndex = queueFamily_;
        poolInfo.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        result = vkCreateCommandPool(device_, &poolInfo, nullptr, &commandPool_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateCommandPool failed");
        }

        commandBuffers_.resize(images_.size(), VK_NULL_HANDLE);
        VkCommandBufferAllocateInfo allocateInfo{};
        allocateInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
        allocateInfo.commandPool = commandPool_;
        allocateInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocateInfo.commandBufferCount = static_cast<uint32_t>(commandBuffers_.size());
        result = vkAllocateCommandBuffers(device_, &allocateInfo, commandBuffers_.data());
        if (result != VK_SUCCESS) {
            return Fail(result, "vkAllocateCommandBuffers failed");
        }

        const VkClearValue clearValue = {{{0.025f, 0.22f, 0.55f, 1.0f}}};
        for (size_t index = 0; index < commandBuffers_.size(); ++index) {
            VkCommandBufferBeginInfo beginInfo{};
            beginInfo.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
            beginInfo.flags = VK_COMMAND_BUFFER_USAGE_SIMULTANEOUS_USE_BIT;
            result = vkBeginCommandBuffer(commandBuffers_[index], &beginInfo);
            if (result != VK_SUCCESS) {
                return Fail(result, "vkBeginCommandBuffer failed");
            }

            VkRenderPassBeginInfo passInfo{};
            passInfo.sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO;
            passInfo.renderPass = renderPass_;
            passInfo.framebuffer = framebuffers_[index];
            passInfo.renderArea.offset = {0, 0};
            passInfo.renderArea.extent = extent_;
            passInfo.clearValueCount = 1;
            passInfo.pClearValues = &clearValue;
            vkCmdBeginRenderPass(
                commandBuffers_[index], &passInfo, VK_SUBPASS_CONTENTS_INLINE);
            vkCmdEndRenderPass(commandBuffers_[index]);
            result = vkEndCommandBuffer(commandBuffers_[index]);
            if (result != VK_SUCCESS) {
                return Fail(result, "vkEndCommandBuffer failed");
            }
        }

        VkSemaphoreCreateInfo semaphoreInfo{};
        semaphoreInfo.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO;
        result = vkCreateSemaphore(device_, &semaphoreInfo, nullptr, &imageAvailable_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateSemaphore(imageAvailable) failed");
        }
        result = vkCreateSemaphore(device_, &semaphoreInfo, nullptr, &renderFinished_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateSemaphore(renderFinished) failed");
        }

        VkFenceCreateInfo fenceInfo{};
        fenceInfo.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO;
        fenceInfo.flags = VK_FENCE_CREATE_SIGNALED_BIT;
        result = vkCreateFence(device_, &fenceInfo, nullptr, &inFlightFence_);
        if (result != VK_SUCCESS) {
            return Fail(result, "vkCreateFence failed");
        }

        recreateRequested_ = false;
        status_.width = extent_.width;
        status_.height = extent_.height;
        status_.imageCount = static_cast<uint32_t>(images_.size());
        status_.formatName = FormatName(surfaceFormat_.format);
        status_.presentModeName = "FIFO";
        status_.resultCode = static_cast<int>(VK_SUCCESS);
        status_.presenting = true;
        WriteBreadcrumb([NSString stringWithFormat:
            @"phase=m2_swapchain_resources_ready extent=%ux%u images=%u format=%s",
            extent_.width,
            extent_.height,
            static_cast<unsigned>(images_.size()),
            status_.formatName.c_str()]);
        return true;
    }

    void DestroySwapchainResources()
    {
        if (device_ == VK_NULL_HANDLE) {
            return;
        }
        if (inFlightFence_ != VK_NULL_HANDLE) {
            vkDestroyFence(device_, inFlightFence_, nullptr);
            inFlightFence_ = VK_NULL_HANDLE;
        }
        if (renderFinished_ != VK_NULL_HANDLE) {
            vkDestroySemaphore(device_, renderFinished_, nullptr);
            renderFinished_ = VK_NULL_HANDLE;
        }
        if (imageAvailable_ != VK_NULL_HANDLE) {
            vkDestroySemaphore(device_, imageAvailable_, nullptr);
            imageAvailable_ = VK_NULL_HANDLE;
        }
        if (commandPool_ != VK_NULL_HANDLE) {
            vkDestroyCommandPool(device_, commandPool_, nullptr);
            commandPool_ = VK_NULL_HANDLE;
        }
        commandBuffers_.clear();
        for (VkFramebuffer framebuffer : framebuffers_) {
            if (framebuffer != VK_NULL_HANDLE) {
                vkDestroyFramebuffer(device_, framebuffer, nullptr);
            }
        }
        framebuffers_.clear();
        if (renderPass_ != VK_NULL_HANDLE) {
            vkDestroyRenderPass(device_, renderPass_, nullptr);
            renderPass_ = VK_NULL_HANDLE;
        }
        for (VkImageView view : imageViews_) {
            if (view != VK_NULL_HANDLE) {
                vkDestroyImageView(device_, view, nullptr);
            }
        }
        imageViews_.clear();
        images_.clear();
        if (swapchain_ != VK_NULL_HANDLE) {
            vkDestroySwapchainKHR(device_, swapchain_, nullptr);
            swapchain_ = VK_NULL_HANDLE;
        }
    }

    void DestroyAll()
    {
        if (device_ != VK_NULL_HANDLE) {
            vkDeviceWaitIdle(device_);
            DestroySwapchainResources();
            vkDestroyDevice(device_, nullptr);
            device_ = VK_NULL_HANDLE;
        }
        if (surface_ != VK_NULL_HANDLE && instance_ != VK_NULL_HANDLE) {
            vkDestroySurfaceKHR(instance_, surface_, nullptr);
            surface_ = VK_NULL_HANDLE;
        }
        if (instance_ != VK_NULL_HANDLE) {
            vkDestroyInstance(instance_, nullptr);
            instance_ = VK_NULL_HANDLE;
        }
        volkFinalize();
        if (moltenVKHandle_ != nullptr) {
            dlclose(moltenVKHandle_);
            moltenVKHandle_ = nullptr;
        }
    }

    CAMetalLayer *layer_ = nil;
    void *moltenVKHandle_ = nullptr;
    VkInstance instance_ = VK_NULL_HANDLE;
    VkSurfaceKHR surface_ = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice_ = VK_NULL_HANDLE;
    VkDevice device_ = VK_NULL_HANDLE;
    VkQueue queue_ = VK_NULL_HANDLE;
    uint32_t queueFamily_ = UINT32_MAX;
    bool portabilitySubset_ = false;

    VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
    VkSurfaceFormatKHR surfaceFormat_{};
    VkExtent2D extent_{};
    std::vector<VkImage> images_;
    std::vector<VkImageView> imageViews_;
    VkRenderPass renderPass_ = VK_NULL_HANDLE;
    std::vector<VkFramebuffer> framebuffers_;
    VkCommandPool commandPool_ = VK_NULL_HANDLE;
    std::vector<VkCommandBuffer> commandBuffers_;
    VkSemaphore imageAvailable_ = VK_NULL_HANDLE;
    VkSemaphore renderFinished_ = VK_NULL_HANDLE;
    VkFence inFlightFence_ = VK_NULL_HANDLE;

    bool paused_ = false;
    bool recreateRequested_ = false;
    SwapchainStatus status_;
};

NSString *StatusText(const SwapchainStatus& status)
{
    NSString *deviceName = [NSString stringWithUTF8String:status.deviceName.c_str()];
    NSString *formatName = [NSString stringWithUTF8String:status.formatName.c_str()];
    NSString *presentMode = [NSString stringWithUTF8String:status.presentModeName.c_str()];
    NSString *detail = [NSString stringWithUTF8String:status.detail.c_str()];
    NSString *queue = status.queueFamily == UINT32_MAX
        ? @"n/a"
        : [NSString stringWithFormat:@"%u", status.queueFamily];
    return [NSString stringWithFormat:
        @"SelacoiOS Milestone 2\n\n"
         "UIKit lifecycle: PASS\n"
         "Metal layer: PASS\n"
         "Vulkan device: %@\n"
         "Swapchain: %@\n"
         "Format: %@\n"
         "Extent: %u × %u\n"
         "Images: %u\n"
         "Present mode: %@\n"
         "Graphics/present queue: %@\n"
         "Frames presented: %llu\n"
         "Last VkResult: %d\n\n%@\n\n"
         "No Selaco.ipk3 loaded\n"
         "No GZSelaco game loop started",
        deviceName,
        status.initialized ? @"PASS" : @"FAIL",
        formatName,
        status.width,
        status.height,
        status.imageCount,
        presentMode,
        queue,
        static_cast<unsigned long long>(status.framesPresented),
        status.resultCode,
        detail];
}

void UncaughtExceptionHandler(NSException *exception)
{
    WriteBreadcrumb([NSString stringWithFormat:
        @"phase=uncaught_objc_exception name=%@ reason=%@",
        exception.name,
        exception.reason ?: @"unknown"]);
}
} // namespace

void CalculateCPUSpeed()
{
    mach_timebase_info_data_t timebase{};
    if (mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.denom != 0) {
        const double nanosecondsPerTick =
            static_cast<double>(timebase.numer) / static_cast<double>(timebase.denom);
        PerfToSec = nanosecondsPerTick * 1.0e-9;
        PerfToMillisec = nanosecondsPerTick * 1.0e-6;
    }
}

void I_GetEvent() {}
void I_SetMouseCapture() {}
void I_ReleaseMouseCapture() {}
void I_LockMouseToWindow() {}
void I_UnlockMouseFromWindow() {}
void I_SetWindowTitle(const char *) {}
void I_OpenShellFolder(const char *) {}

bool I_SetCursor(FGameTexture *)
{
    return false;
}

void I_PrintStr(const char *message)
{
    if (message != nullptr) {
        std::fputs(message, stdout);
        std::fflush(stdout);
    }
}

FString I_GetCWD()
{
    return [NSFileManager defaultManager].currentDirectoryPath.fileSystemRepresentation;
}

FString M_GetAppDataPath(bool create)
{
    return AppSupportPath(create);
}

FString M_GetCachePath(bool create)
{
    return PathForDirectory(NSCachesDirectory, "Selaco", create);
}

FString M_GetConfigPath(bool)
{
    return AppSupportPath(true) + "/selaco.ini";
}

FString M_GetDocumentsPath()
{
    return DocumentsPath(nullptr, true);
}

FString M_GetSavegamesPath()
{
    return DocumentsPath("Savegames", true);
}

void M_GetSavegamesPaths(TArray<FString>& paths)
{
    paths.Push(M_GetSavegamesPath());
}

FString M_GetScreenshotsPath()
{
    return DocumentsPath("Screenshots", true);
}

@interface SelacoSwapchainViewController : UIViewController {
@private
    std::unique_ptr<VulkanSwapchainPresenter> _presenter;
}
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@property(nonatomic, strong) CADisplayLink *displayLink;
@property(nonatomic, assign) BOOL initializationStarted;
@end

@implementation SelacoSwapchainViewController

- (void)loadView
{
    UIView *root = [[UIView alloc] initWithFrame:CGRectZero];
    root.backgroundColor = UIColor.blackColor;
    self.view = root;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    label.layer.cornerRadius = 12.0;
    label.layer.masksToBounds = YES;
    label.font = [UIFont monospacedSystemFontOfSize:14.0 weight:UIFontWeightSemibold];
    label.text = @"SelacoiOS Milestone 2\n\nUIKit: PASS\nPreparing Metal and Vulkan swapchain…";
    [root addSubview:label];
    self.statusLabel = label;

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [label.widthAnchor constraintLessThanOrEqualToAnchor:root.safeAreaLayoutGuide.widthAnchor multiplier:0.82],
    ]];
    WriteBreadcrumb(@"phase=m2_view_loaded");
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    if (self.metalLayer == nil) {
        return;
    }
    self.metalLayer.frame = self.view.bounds;
    const CGFloat scale = UIScreen.mainScreen.scale;
    const CGSize points = self.view.bounds.size;
    const CGSize pixels = CGSizeMake(points.width * scale, points.height * scale);
    self.metalLayer.drawableSize = pixels;
    SelacoIOSSetDrawableSize(
        std::max(1, static_cast<int>(pixels.width)),
        std::max(1, static_cast<int>(pixels.height)));
    if (_presenter) {
        _presenter->RequestRecreate();
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.initializationStarted) {
        return;
    }
    self.initializationStarted = YES;
    WriteBreadcrumb(@"phase=m2_uikit_visible");

    id<MTLDevice> metalDevice = MTLCreateSystemDefaultDevice();
    if (metalDevice == nil) {
        self.statusLabel.text = @"UIKit: PASS\nMetal device: FAIL";
        WriteBreadcrumb(@"phase=m2_metal_device_unavailable");
        return;
    }

    CAMetalLayer *layer = [CAMetalLayer layer];
    layer.device = metalDevice;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    layer.contentsScale = UIScreen.mainScreen.scale;
    [self.view.layer insertSublayer:layer atIndex:0];
    self.metalLayer = layer;
    [self viewDidLayoutSubviews];
    WriteBreadcrumb(@"phase=m2_metal_layer_ready");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.75 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            _presenter = std::make_unique<VulkanSwapchainPresenter>(self.metalLayer);
            if (!_presenter->Initialize()) {
                NSString *text = StatusText(_presenter->Status());
                self.statusLabel.text = text;
                WriteStatusSnapshot(text);
                return;
            }

            NSString *text = StatusText(_presenter->Status());
            self.statusLabel.text = text;
            WriteStatusSnapshot(text);

            self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                           selector:@selector(renderFrame:)];
            [self.displayLink addToRunLoop:NSRunLoop.mainRunLoop
                                   forMode:NSRunLoopCommonModes];
            WriteBreadcrumb(@"phase=m2_display_link_started");

            [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(applicationWillResignActive:)
                       name:UIApplicationWillResignActiveNotification
                     object:nil];
            [[NSNotificationCenter defaultCenter]
                addObserver:self
                   selector:@selector(applicationDidBecomeActive:)
                       name:UIApplicationDidBecomeActiveNotification
                     object:nil];
        }
        @catch (NSException *exception) {
            NSString *message = [NSString stringWithFormat:
                @"phase=m2_objc_exception name=%@ reason=%@",
                exception.name,
                exception.reason ?: @"unknown"];
            WriteBreadcrumb(message);
            self.statusLabel.text = message;
        }
    });
}

- (void)renderFrame:(CADisplayLink *)displayLink
{
    (void)displayLink;
    if (!_presenter) {
        return;
    }
    VkResult result = _presenter->DrawFrame();
    const SwapchainStatus& status = _presenter->Status();
    if (status.framesPresented == 1 || status.framesPresented % 30 == 0 ||
        (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR &&
         result != VK_ERROR_OUT_OF_DATE_KHR && result != VK_NOT_READY)) {
        NSString *text = StatusText(status);
        self.statusLabel.text = text;
        WriteStatusSnapshot(text);
    }
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR &&
        result != VK_ERROR_OUT_OF_DATE_KHR && result != VK_NOT_READY) {
        self.displayLink.paused = YES;
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    (void)notification;
    self.displayLink.paused = YES;
    if (_presenter) {
        _presenter->Pause();
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    (void)notification;
    if (_presenter) {
        _presenter->Resume();
    }
    self.displayLink.paused = NO;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.displayLink invalidate];
    self.displayLink = nil;
    _presenter.reset();
}

@end

@interface SelacoSwapchainAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SelacoSwapchainAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;
    WriteBreadcrumb(@"phase=m2_app_delegate_entered");
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[SelacoSwapchainViewController alloc] init];
    [self.window makeKeyAndVisible];
    WriteBreadcrumb(@"phase=m2_window_visible");
    return YES;
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&UncaughtExceptionHandler);
        WriteBreadcrumb(@"phase=m2_main_entered");
        return UIApplicationMain(
            argc,
            argv,
            nil,
            NSStringFromClass(SelacoSwapchainAppDelegate.class));
    }
}
