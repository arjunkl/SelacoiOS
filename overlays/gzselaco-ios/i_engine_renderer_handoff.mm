// SelacoiOS Milestone 4B diagnostic-to-engine Vulkan renderer handoff.
//
// UIKit and CAMetalLayer remain app-owned. The diagnostic presenter is destroyed
// before this source lets the pinned GZSelaco Vulkan backend create a fresh
// instance, Metal surface, device, swapchain, framebuffer, and renderer state.

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#define VK_USE_PLATFORM_METAL_EXT 1
#define VK_NO_PROTOTYPES 1
#include "zvulkan/volk/volk.h"

#include <dlfcn.h>
#include <memory>
#include <string>

#include "c_cvars.h"
#include "i_video.h"
#include "i_system.h"
#include "printf.h"
#include "v_video.h"
#include "vulkan/system/vk_renderdevice.h"
#include <zvulkan/vulkanbuilders.h>
#include <zvulkan/vulkaninstance.h>
#include <zvulkan/vulkansurface.h>

EXTERN_CVAR(Bool, vk_debug)
EXTERN_CVAR(Bool, vid_fullscreen)

extern "C" void SelacoIOSReportLicensedAssetProbe(
    const char *phase,
    const char *detail);

namespace {
CAMetalLayer *gEngineMetalLayer = nil;
void *gEngineMoltenVKHandle = nullptr;
PFN_vkGetInstanceProcAddr gEngineGetInstanceProcAddr = nullptr;

class IOSVideo final : public IVideo
{
public:
    DFrameBuffer *CreateFrameBuffer() override
    {
        if (gEngineMetalLayer == nil || gEngineMetalLayer.device == nil) {
            VulkanError("SelacoiOS engine renderer has no registered CAMetalLayer");
        }

        SelacoIOSReportLicensedAssetProbe(
            "engine_vulkan_instance_create_entered",
            "VulkanInstanceBuilder with VK_EXT_metal_surface");

        VulkanInstanceBuilder builder;
        builder.DebugLayer(vk_debug);
        builder.RequireExtension(VK_KHR_SURFACE_EXTENSION_NAME);
        builder.RequireExtension(VK_EXT_METAL_SURFACE_EXTENSION_NAME);
        builder.RequireExtension(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        auto instance = builder.Create();

        SelacoIOSReportLicensedAssetProbe(
            "engine_vulkan_instance_create_passed",
            "GZSelaco VulkanInstance created through embedded MoltenVK");

        VkMetalSurfaceCreateInfoEXT surfaceInfo{};
        surfaceInfo.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
        surfaceInfo.pLayer = gEngineMetalLayer;

        VkSurfaceKHR surfaceHandle = VK_NULL_HANDLE;
        const VkResult result = vkCreateMetalSurfaceEXT(
            instance->Instance, &surfaceInfo, nullptr, &surfaceHandle);
        if (result != VK_SUCCESS) {
            NSString *detail = [NSString stringWithFormat:
                @"vkCreateMetalSurfaceEXT failed with VkResult %d",
                static_cast<int>(result)];
            SelacoIOSReportLicensedAssetProbe(
                "engine_metal_surface_create_failed",
                detail.UTF8String);
            VulkanError("SelacoiOS vkCreateMetalSurfaceEXT failed");
        }

        SelacoIOSReportLicensedAssetProbe(
            "engine_metal_surface_create_passed",
            "GZSelaco owns a new VkMetalSurfaceEXT on the existing CAMetalLayer");

        surface_ = std::make_shared<VulkanSurface>(instance, surfaceHandle);

        SelacoIOSReportLicensedAssetProbe(
            "engine_render_device_construct_entered",
            "constructing VulkanRenderDevice");
        auto *framebuffer = new VulkanRenderDevice(
            nullptr, static_cast<bool>(vid_fullscreen), surface_);
        SelacoIOSReportLicensedAssetProbe(
            "engine_render_device_construct_passed",
            "VulkanRenderDevice selected a compatible device and queue topology");
        return framebuffer;
    }

    void DumpAdapters() override
    {
        const CGSize size = gEngineMetalLayer == nil
            ? CGSizeZero
            : gEngineMetalLayer.drawableSize;
        Printf("0. Apple Metal drawable %.0f x %.0f\n", size.width, size.height);
    }

    void DumpAdapters(TArray<FString>& adapters) override
    {
        const CGSize size = gEngineMetalLayer == nil
            ? CGSizeZero
            : gEngineMetalLayer.drawableSize;
        adapters.Push(FStringf(
            "0. Apple Metal drawable %.0f x %.0f",
            size.width,
            size.height));
    }

private:
    std::shared_ptr<VulkanSurface> surface_;
};
} // namespace

extern "C" void SelacoIOSRegisterEngineMetalLayer(CAMetalLayer *layer)
{
    gEngineMetalLayer = layer;
    SelacoIOSReportLicensedAssetProbe(
        layer == nil ? "engine_metal_layer_registration_failed"
                     : "engine_metal_layer_registered",
        layer == nil ? "CAMetalLayer is nil"
                     : "UIKit CAMetalLayer retained for GZSelaco renderer ownership");
}

extern "C" PFN_vkGetInstanceProcAddr SelacoIOSGetVkGetInstanceProcAddr()
{
    if (gEngineGetInstanceProcAddr != nullptr) {
        return gEngineGetInstanceProcAddr;
    }

    NSString *frameworkBinary = [[NSBundle mainBundle]
        pathForResource:@"MoltenVK"
                 ofType:nil
            inDirectory:@"Frameworks/MoltenVK.framework"];
    if (frameworkBinary == nil) {
        SelacoIOSReportLicensedAssetProbe(
            "engine_moltenvk_loader_failed",
            "embedded MoltenVK.framework binary is missing");
        return nullptr;
    }

    gEngineMoltenVKHandle = dlopen(
        frameworkBinary.fileSystemRepresentation,
        RTLD_NOW | RTLD_LOCAL);
    if (gEngineMoltenVKHandle == nullptr) {
        const char *error = dlerror();
        SelacoIOSReportLicensedAssetProbe(
            "engine_moltenvk_loader_failed",
            error == nullptr ? "dlopen MoltenVK failed" : error);
        return nullptr;
    }

    gEngineGetInstanceProcAddr =
        reinterpret_cast<PFN_vkGetInstanceProcAddr>(
            dlsym(gEngineMoltenVKHandle, "vkGetInstanceProcAddr"));
    if (gEngineGetInstanceProcAddr == nullptr) {
        SelacoIOSReportLicensedAssetProbe(
            "engine_moltenvk_loader_failed",
            "MoltenVK lacks vkGetInstanceProcAddr");
        return nullptr;
    }

    SelacoIOSReportLicensedAssetProbe(
        "engine_moltenvk_loader_passed",
        "embedded MoltenVK vkGetInstanceProcAddr resolved for GZSelaco");
    return gEngineGetInstanceProcAddr;
}

IVideo *gl_CreateVideo()
{
    return new IOSVideo();
}

void I_FocusWindow()
{
    // UIKit already owns the active application window.
}

void I_InitGraphics()
{
    SelacoIOSReportLicensedAssetProbe(
        "i_init_graphics_entered",
        "creating the iOS GZSelaco Vulkan video backend");

    if (Video == nullptr) {
        Video = gl_CreateVideo();
    }
    if (Video == nullptr) {
        I_FatalError("SelacoiOS failed to create the engine video backend");
    }

    SelacoIOSReportLicensedAssetProbe(
        "i_init_graphics_passed",
        "iOS GZSelaco Vulkan video backend ready");
}
