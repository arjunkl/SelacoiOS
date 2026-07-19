// SelacoiOS Milestone 1 physical-runtime bootstrap.
//
// This keeps the complete GZSelaco engine linked into the application while
// UIKit owns process lifetime. The runtime gate creates an iOS CAMetalLayer,
// creates and destroys a Vulkan instance and metal surface, enumerates a
// physical device and a present-capable graphics queue, then displays and
// persists the result. It does not load proprietary game data, create a
// swapchain, or enter the GZSelaco game loop.

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
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:&error];
        if (error != nil) {
            std::fprintf(stderr, "SelacoiOS: unable to create %s: %s\n",
                path.fileSystemRepresentation,
                error.localizedDescription.UTF8String);
        }
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
    if (layer == nil || layer.device == nil) {
        output.detail = "CAMetalLayer or Metal device is unavailable";
        return output;
    }

    uint32_t extensionCount = 0;
    VkResult result = vkEnumerateInstanceExtensionProperties(
        nullptr, &extensionCount, nullptr);
    if (result != VK_SUCCESS) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkEnumerateInstanceExtensionProperties(count) failed";
        return output;
    }

    std::vector<VkExtensionProperties> extensions(extensionCount);
    if (extensionCount > 0) {
        result = vkEnumerateInstanceExtensionProperties(
            nullptr, &extensionCount, extensions.data());
        if (result != VK_SUCCESS && result != VK_INCOMPLETE) {
            output.resultCode = static_cast<int>(result);
            output.detail = "vkEnumerateInstanceExtensionProperties(list) failed";
            return output;
        }
    }

    if (!HasInstanceExtension(extensions, VK_KHR_SURFACE_EXTENSION_NAME) ||
        !HasInstanceExtension(extensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME)) {
        output.resultCode = static_cast<int>(VK_ERROR_EXTENSION_NOT_PRESENT);
        output.detail = "VK_KHR_surface or VK_EXT_metal_surface is unavailable";
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
    applicationInfo.applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
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

    VkInstance instance = VK_NULL_HANDLE;
    result = vkCreateInstance(&instanceInfo, nullptr, &instance);
    if (result != VK_SUCCESS) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkCreateInstance failed";
        return output;
    }

    VkMetalSurfaceCreateInfoEXT surfaceInfo{};
    surfaceInfo.sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT;
    surfaceInfo.pLayer = layer;

    VkSurfaceKHR surface = VK_NULL_HANDLE;
    result = vkCreateMetalSurfaceEXT(instance, &surfaceInfo, nullptr, &surface);
    if (result != VK_SUCCESS) {
        output.resultCode = static_cast<int>(result);
        output.detail = "vkCreateMetalSurfaceEXT failed";
        vkDestroyInstance(instance, nullptr);
        return output;
    }

    uint32_t physicalDeviceCount = 0;
    result = vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, nullptr);
    if (result != VK_SUCCESS || physicalDeviceCount == 0) {
        output.resultCode = result == VK_SUCCESS
            ? static_cast<int>(VK_ERROR_INITIALIZATION_FAILED)
            : static_cast<int>(result);
        output.detail = "no Vulkan physical device was enumerated";
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
        vkDestroySurfaceKHR(instance, surface, nullptr);
        vkDestroyInstance(instance, nullptr);
        return output;
    }

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
    }

    vkDestroySurfaceKHR(instance, surface, nullptr);
    vkDestroyInstance(instance, nullptr);
    return output;
}

void PersistRuntimeResult(NSString *text)
{
    FString documents = DocumentsPath(nullptr, true);
    if (documents.IsEmpty()) {
        return;
    }

    NSString *root = [NSString stringWithUTF8String:documents.GetChars()];
    NSString *path = [root stringByAppendingPathComponent:@"runtime-bootstrap.txt"];
    NSError *error = nil;
    [text writeToFile:path
           atomically:YES
             encoding:NSUTF8StringEncoding
                error:&error];
    if (error != nil) {
        std::fprintf(stderr, "SelacoiOS: unable to persist runtime result: %s\n",
            error.localizedDescription.UTF8String);
    }
}
} // namespace

void CalculateCPUSpeed()
{
#if defined(__aarch64__)
    uint64_t frequency = 0;
    __asm__ volatile("mrs %0, cntfrq_el0" : "=r"(frequency));
    if (frequency != 0) {
        PerfToSec = 1.0 / static_cast<double>(frequency);
        PerfToMillisec = 1000.0 / static_cast<double>(frequency);
    }
#else
    mach_timebase_info_data_t timebase{};
    if (mach_timebase_info(&timebase) == KERN_SUCCESS && timebase.denom != 0) {
        const double nanosecondsPerTick =
            static_cast<double>(timebase.numer) / static_cast<double>(timebase.denom);
        PerfToSec = nanosecondsPerTick * 1.0e-9;
        PerfToMillisec = nanosecondsPerTick * 1.0e-6;
    }
#endif
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

@interface SelacoRuntimeView : UIView
@end

@implementation SelacoRuntimeView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

@interface SelacoRuntimeViewController : UIViewController
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, assign) BOOL testStarted;
@end

@implementation SelacoRuntimeViewController

- (void)loadView
{
    SelacoRuntimeView *root = [[SelacoRuntimeView alloc] initWithFrame:CGRectZero];
    root.backgroundColor = [UIColor colorWithRed:0.018 green:0.025 blue:0.045 alpha:1.0];
    self.view = root;

    CAMetalLayer *metalLayer = (CAMetalLayer *)root.layer;
    metalLayer.device = MTLCreateSystemDefaultDevice();
    metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    metalLayer.framebufferOnly = YES;
    metalLayer.contentsScale = UIScreen.mainScreen.scale;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont monospacedSystemFontOfSize:16.0 weight:UIFontWeightSemibold];
    label.text = @"SelacoiOS\nFull GZSelaco engine linked\nStarting Vulkan + Metal runtime probe…";
    [root addSubview:label];
    self.statusLabel = label;

    [NSLayoutConstraint activateConstraints:@[
        [label.centerXAnchor constraintEqualToAnchor:root.centerXAnchor],
        [label.centerYAnchor constraintEqualToAnchor:root.centerYAnchor],
        [label.leadingAnchor constraintGreaterThanOrEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [label.trailingAnchor constraintLessThanOrEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
    ]];
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CAMetalLayer *metalLayer = (CAMetalLayer *)self.view.layer;
    const CGFloat scale = UIScreen.mainScreen.scale;
    const CGSize points = self.view.bounds.size;
    const CGSize pixels = CGSizeMake(points.width * scale, points.height * scale);
    metalLayer.drawableSize = pixels;
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

    dispatch_async(dispatch_get_main_queue(), ^{
        CAMetalLayer *metalLayer = (CAMetalLayer *)self.view.layer;
        VulkanBootstrapResult result = RunVulkanBootstrap(metalLayer);
        NSString *device = result.deviceName.empty()
            ? @"not enumerated"
            : [NSString stringWithUTF8String:result.deviceName.c_str()];
        NSString *detail = [NSString stringWithUTF8String:result.detail.c_str()];
        NSString *status = result.passed ? @"PASS" : @"FAIL";
        NSString *queue = result.queueFamily == UINT32_MAX
            ? @"n/a"
            : [NSString stringWithFormat:@"%u", result.queueFamily];

        NSString *text = [NSString stringWithFormat:
            @"SelacoiOS Runtime Bootstrap\n\n"
             "Complete GZSelaco engine: LINKED\n"
             "UIKit lifecycle: ACTIVE\n"
             "MoltenVK instance + Metal surface: %@\n"
             "Physical device: %@\n"
             "Graphics/present queue: %@\n"
             "VkResult: %d\n\n"
             "%@\n\n"
             "No Selaco.ipk3 loaded\n"
             "No swapchain or game loop started",
            status,
            device,
            queue,
            result.resultCode,
            detail];
        self.statusLabel.text = text;
        PersistRuntimeResult(text);
        std::fprintf(stdout, "%s\n", text.UTF8String);
        std::fflush(stdout);
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
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[SelacoRuntimeViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char **argv)
{
    @autoreleasepool {
        static FArgs processArgs(argc, argv);
        Args = &processArgs;
        CalculateCPUSpeed();
        return UIApplicationMain(
            argc,
            argv,
            nil,
            NSStringFromClass(SelacoRuntimeAppDelegate.class));
    }
}
