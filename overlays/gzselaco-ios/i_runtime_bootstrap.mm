// SelacoiOS Milestone 1.1 crash-localization runtime bootstrap.
//
// The complete GZSelaco engine remains linked, but UIKit is entered before any
// engine-owned process initialization. A plain UIKit screen is made visible
// first, then Metal and Vulkan are introduced in delayed, breadcrumbed phases.
// No proprietary game data, swapchain, or engine loop is started.

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <UIKit/UIKit.h>

#define VK_USE_PLATFORM_METAL_EXT 1
#include <vulkan/vulkan.h>

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <mach/mach_time.h>
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

NSString *DiagnosticPath()
{
    NSString *directory = DiagnosticDirectory();
    return directory == nil
        ? nil
        : [directory stringByAppendingPathComponent:@"runtime-bootstrap.txt"];
}

void WriteBreadcrumb(NSString *phase)
{
    if (phase == nil) {
        return;
    }

    NSString *path = DiagnosticPath();
    if (path != nil) {
        NSString *existing = [NSString stringWithContentsOfFile:path
                                                       encoding:NSUTF8StringEncoding
                                                          error:nil];
        if (existing == nil) {
            existing = @"SelacoiOS Milestone 1.1 crash-localization log\n";
        }
        NSString *line = [NSString stringWithFormat:@"%@\n", phase];
        NSString *updated = [existing stringByAppendingString:line];
        [updated writeToFile:path
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:nil];
    }

    std::fprintf(stderr, "SelacoiOS phase: %s\n", phase.UTF8String);
    std::fflush(stderr);
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

bool HasInstanceExtension(
    const std::vector<VkExtensionProperties>& extensions,
    const char *name)
{
    for (const VkExtensionProperties& extension : extensions) {
        if (std::strcmp(extension.extensionName, name) == 0) {
            return true;
        }
    }
    return false;
}

struct VulkanBootstrapResult
{
    bool passed = false;
    int resultCode = static_cast<int>(VK_ERROR_INITIALIZATION_FAILED);
    std::string deviceName;
    uint32_t queueFamily = UINT32_MAX;
    std::string detail;
};

VulkanBootstrapResult RunVulkanBootstrap(CAMetalLayer *layer)
{
    VulkanBootstrapResult output;
    WriteBreadcrumb(@"phase=vulkan_probe_entered");

    if (layer == nil || layer.device == nil) {
        output.detail = "CAMetalLayer or Metal device is unavailable";
        WriteBreadcrumb(@"phase=vulkan_probe_failed_layer_unavailable");
        return output;
    }

    WriteBreadcrumb(@"phase=vulkan_enumerate_instance_extensions");
    uint32_t extensionCount = 0;
    VkResult result = vkEnumerateInstanceExtensionProperties(
        nullptr, &extensionCount, nullptr);
    if (result != VK_SUCCESS) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkEnumerateInstanceExtensionProperties(count) failed";
        WriteBreadcrumb(@"phase=vulkan_instance_extension_count_failed");
        return output;
    }

    std::vector<VkExtensionProperties> extensions(extensionCount);
    if (extensionCount > 0) {
        result = vkEnumerateInstanceExtensionProperties(
            nullptr, &extensionCount, extensions.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            output.resultCode = static_cast<int>(result);
            output.detail = "vkEnumerateInstanceExtensionProperties(list) failed";
            WriteBreadcrumb(@"phase=vulkan_instance_extension_list_failed");
            return output;
        }
    }

    if (!HasInstanceExtension(extensions, VK_KHR_SURFACE_EXTENSION_NAME) ||
        !HasInstanceExtension(extensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME)) {
        output.resultCode = static_cast<int>(VK_ERROR_EXTENSION_NOT_PRESENT);
        output.detail = "VK_KHR_surface or VK_EXT_metal_surface is unavailable";
        WriteBreadcrumb(@"phase=vulkan_required_extensions_missing");
        return output;
    }

    const bool hasPortabilityEnumeration = HasInstanceExtension(
        extensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
    const char *enabledExtensions[3] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };

    VkApplicationInfo applicationInfo{};
    applicationInfo.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    applicationInfo.pApplicationName = "SelacoiOS Runtime Bootstrap";
    applicationInfo.applicationVersion = VK_MAKE_API_VERSION(0, 0, 2, 0);
    applicationInfo.pEngineName = "GZSelaco iOS Runtime Boundary";
    applicationInfo.engineVersion = VK_MAKE_API_VERSION(0, 4, 13, 0);
    applicationInfo.apiVersion = VK_API_VERSION_1_1;

    VkInstanceCreateInfo instanceInfo{};
    instanceInfo.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    instanceInfo.pApplicationInfo = &applicationInfo;
    instanceInfo.enabledExtensionCount = hasPortabilityEnumeration ? 3U : 2U;
    instanceInfo.ppEnabledExtensionNames = enabledExtensions;
    if (hasPortabilityEnumeration) {
        instanceInfo.flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    WriteBreadcrumb(@"phase=vulkan_create_instance");
    VkInstance instance = VK_NULL_HANDLE;
    result = vkCreateInstance(&instanceInfo, nullptr, &instance);
    if (result != VK_SUCCESS) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkCreateInstance failed";
        WriteBreadcrumb(@"phase=vulkan_create_instance_failed");
        return output;
    }
    WriteBreadcrumb(@"phase=vulkan_instance_created");

    VkMetalSurfaceCreateInfoEXT surfaceInfo{};
    surfaceInfo.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surfaceInfo.pLayer = layer;

    WriteBreadcrumb(@"phase=vulkan_create_metal_surface");
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = vkCreateMetalSurfaceEXT(instance, &surfaceInfo, nullptr, &surface);
    if (result != VK_SUCCESS) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkCreateMetalSurfaceEXT failed";
        WriteBreadcrumb(@"phase=vulkan_create_metal_surface_failed");
        vkDestroyInstance(instance, nullptr);
        return output;
    }
    WriteBreadcrumb(@"phase=vulkan_metal_surface_created");

    uint32_t physicalDeviceCount = 0;
    result = vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, nullptr);
    if (result != VK_SUCCESS || physicalDeviceCount == 0) {
        output.resultCode = result == VK_SUCCESS
            ? static_cast<int>(VK_ERROR_INITIALIZATION_FAILED)
            : static_cast<int>(result);
        output.detail = "no Vulkan physical device was enumerated";
        WriteBreadcrumb(@"phase=vulkan_physical_device_count_failed");
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return output;
    }

    std::vector<VkPhysicalDevice> physicalDevices(physicalDeviceCount);
    result = vkEnumeratePhysicalDevices(
        instance, &physicalDeviceCount, physicalDevices.data());
    if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkEnumeratePhysicalDevices(list) failed";
        WriteBreadcrumb(@"phase=vulkan_physical_device_list_failed");
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return output;
    }
    WriteBreadcrumb(@"phase=vulkan_physical_devices_enumerated");

    for (VkPhysicalDevice physicalDevice : physicalDevices) {
        VkPhysicalDeviceProperties properties{};
        vkGetPhysicalDeviceProperties(physicalDevice, &properties);

        uint32_t queueCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(physicalDevice, &queueCount, nullptr);
        std::vector<VkQueueFamilyProperties> queues(queueCount);
        if (queueCount > 0) {
            vkGetPhysicalDeviceQueueFamilyProperties(
                physicalDevice, &queueCount, queues.data());
        }

        for (uint32_t queueIndex = 0; queueIndex < queueCount; ++queueIndex) {
            if ((queues[queueIndex].queueFlags & VK_QUEUE_GRAPHICS_BIT) == 0) {
                continue;
            }

            VkBool32 presentSupported = VK_FALSE;
            result = vkGetPhysicalDeviceSurfaceSupportKHR(
                physicalDevice, queueIndex, surface, &presentSupported);
            if (result == VK_SUCCESS && presentSupported == VK_TRUE) {
                output.passed = true;
                output.resultCode = static_cast<int>(VK_SUCCESS);
                output.deviceName = properties.deviceName;
                output.queueFamily = queueIndex;
                output.detail = "instance, physical device, graphics/present queue, and Metal surface passed";
                break;
            }
        }

        if (output.passed) {
            break;
        }
    }

    if (!output.passed) {
        output.resultCode = static_cast<int>(VK_ERROR_FEATURE_NOT_PRESENT);
        output.detail = "no graphics queue reported Metal-surface presentation support";
        WriteBreadcrumb(@"phase=vulkan_present_queue_not_found");
    } else {
        WriteBreadcrumb(@"phase=vulkan_probe_passed");
    }

    vkDestroySurfaceKHR(instance, surface, nullptr);
    vkDestroyInstance(instance, nullptr);
    WriteBreadcrumb(@"phase=vulkan_resources_destroyed");
    return output;
}

void UncaughtExceptionHandler(NSException *exception)
{
    NSString *message = [NSString stringWithFormat:
        @"phase=uncaught_objc_exception name=%@ reason=%@",
        exception.name,
        exception.reason ?: @"unknown"];
    WriteBreadcrumb(message);
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
    if (message == nullptr) {
        return;
    }
    std::fputs(message, stdout);
    std::fflush(stdout);
}

FString I_GetCWD()
{
    NSString *path = [NSFileManager defaultManager].currentDirectoryPath;
    return path.fileSystemRepresentation;
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
    FString root = AppSupportPath(true);
    return root + "/selaco.ini";
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

@interface SelacoRuntimeViewController : UIViewController
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) CAMetalLayer *metalLayer;
@property(nonatomic, assign) BOOL testStarted;
@end

@implementation SelacoRuntimeViewController

- (void)loadView
{
    WriteBreadcrumb(@"phase=view_load_entered");
    UIView *root = [[UIView alloc] initWithFrame:CGRectZero];
    root.backgroundColor = [UIColor colorWithRed:0.018 green:0.025 blue:0.045 alpha:1.0];
    self.view = root;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedSystemFontOfSize:16.0 weight:UIFontWeightSemibold];
    label.text = @"SelacoiOS Crash-Localization Build\n\nUIKit view created\nWaiting before Metal initialization…";
    [root addSubview:label];
    self.statusLabel = label;

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
    ]];
    WriteBreadcrumb(@"phase=view_load_completed");
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
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (self.testStarted) {
        return;
    }
    self.testStarted = YES;
    WriteBreadcrumb(@"phase=uikit_view_visible");

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        @try {
            self.statusLabel.text = @"SelacoiOS Crash-Localization Build\n\nUIKit: PASS\nCreating Metal device and CAMetalLayer…";
            WriteBreadcrumb(@"phase=metal_device_create_entered");
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            if (device == nil) {
                self.statusLabel.text = @"UIKit: PASS\nMetal device: FAIL";
                WriteBreadcrumb(@"phase=metal_device_unavailable");
                return;
            }

            CAMetalLayer *layer = [CAMetalLayer layer];
            layer.device = device;
            layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
            layer.framebufferOnly = YES;
            layer.contentsScale = UIScreen.mainScreen.scale;
            [self.view.layer insertSublayer:layer atIndex:0];
            self.metalLayer = layer;
            [self viewDidLayoutSubviews];
            WriteBreadcrumb(@"phase=metal_layer_ready");
            self.statusLabel.text = @"SelacoiOS Crash-Localization Build\n\nUIKit: PASS\nMetal layer: PASS\nWaiting before Vulkan probe…";

            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                @try {
                    self.statusLabel.text = @"SelacoiOS Crash-Localization Build\n\nUIKit: PASS\nMetal layer: PASS\nRunning Vulkan probe…";
                    VulkanBootstrapResult result = RunVulkanBootstrap(self.metalLayer);
                    NSString *deviceName = result.deviceName.empty()
                        ? @"not enumerated"
                        : [NSString stringWithUTF8String:result.deviceName.c_str()];
                    NSString *detail = [NSString stringWithUTF8String:result.detail.c_str()];
                    NSString *queue = result.queueFamily == UINT32_MAX
                        ? @"n/a"
                        : [NSString stringWithFormat:@"%u", result.queueFamily];
                    NSString *status = result.passed ? @"PASS" : @"FAIL";
                    NSString *text = [NSString stringWithFormat:
                        @"SelacoiOS Crash-Localization Build\n\n"
                         "UIKit lifecycle: PASS\n"
                         "Metal layer: PASS\n"
                         "Vulkan + Metal surface: %@\n"
                         "Physical device: %@\n"
                         "Graphics/present queue: %@\n"
                         "VkResult: %d\n\n%@\n\n"
                         "No Selaco.ipk3 loaded\n"
                         "No swapchain or game loop started",
                        status,
                        deviceName,
                        queue,
                        result.resultCode,
                        detail];
                    self.statusLabel.text = text;
                    WriteBreadcrumb([NSString stringWithFormat:
                        @"phase=probe_completed result=%@ code=%d device=%@ queue=%@",
                        status,
                        result.resultCode,
                        deviceName,
                        queue]);
                }
                @catch (NSException *exception) {
                    NSString *message = [NSString stringWithFormat:
                        @"phase=vulkan_objc_exception name=%@ reason=%@",
                        exception.name,
                        exception.reason ?: @"unknown"];
                    WriteBreadcrumb(message);
                    self.statusLabel.text = message;
                }
            });
        }
        @catch (NSException *exception) {
            NSString *message = [NSString stringWithFormat:
                @"phase=metal_objc_exception name=%@ reason=%@",
                exception.name,
                exception.reason ?: @"unknown"];
            WriteBreadcrumb(message);
            self.statusLabel.text = message;
        }
    });
}

@end

@interface SelacoRuntimeAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SelacoRuntimeAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;
    WriteBreadcrumb(@"phase=app_delegate_entered");
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[SelacoRuntimeViewController alloc] init];
    [self.window makeKeyAndVisible];
    WriteBreadcrumb(@"phase=window_visible");
    return YES;
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        NSSetUncaughtExceptionHandler(&UncaughtExceptionHandler);
        WriteBreadcrumb(@"phase=main_entered");
        return UIApplicationMain(
            argc,
            argv,
            nil,
            NSStringFromClass(SelacoRuntimeAppDelegate.class));
    }
}
