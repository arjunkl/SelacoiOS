#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <UIKit/UIKit.h>

#include "SelacoEngineBoundary.h"

@interface SelacoShellViewController : UIViewController <MTKViewDelegate>
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@end

@implementation SelacoShellViewController

- (void)loadView
{
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTKView *metalView = [[MTKView alloc] initWithFrame:CGRectZero device:device];
    metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    metalView.clearColor = MTLClearColorMake(0.025, 0.035, 0.055, 1.0);
    metalView.delegate = self;
    metalView.preferredFramesPerSecond = 60;
    self.view = metalView;

    self.commandQueue = [device newCommandQueue];

    NSString *signature = [NSString stringWithUTF8String:SelacoIOSGameSignature()];
    NSString *engine = [NSString stringWithUTF8String:SelacoIOSEngineVersion()];
    NSString *queueStatus = SelacoIOSQueueSelfTest() ? @"PASS" : @"FAIL";

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.numberOfLines = 0;
    status.textAlignment = NSTextAlignmentCenter;
    status.textColor = UIColor.whiteColor;
    status.font = [UIFont monospacedSystemFontOfSize:18.0 weight:UIFontWeightSemibold];
    status.text = [NSString stringWithFormat:
        @"SelacoiOS\n%@ · %@\nPinned engine bridge: %@\nMilestone 0 platform shell",
        signature,
        engine,
        queueStatus];
    [metalView addSubview:status];

    [NSLayoutConstraint activateConstraints:@[
        [status.centerXAnchor constraintEqualToAnchor:metalView.centerXAnchor],
        [status.centerYAnchor constraintEqualToAnchor:metalView.centerYAnchor],
        [status.leadingAnchor constraintGreaterThanOrEqualToAnchor:metalView.safeAreaLayoutGuide.leadingAnchor constant:24.0],
        [status.trailingAnchor constraintLessThanOrEqualToAnchor:metalView.safeAreaLayoutGuide.trailingAnchor constant:-24.0],
    ]];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size
{
    (void)view;
    (void)size;
}

- (void)drawInMTKView:(MTKView *)view
{
    MTLRenderPassDescriptor *descriptor = view.currentRenderPassDescriptor;
    id<CAMetalDrawable> drawable = view.currentDrawable;
    if (descriptor == nil || drawable == nil || self.commandQueue == nil) {
        return;
    }

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:descriptor];
    [encoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
}

@end

@interface SelacoShellAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation SelacoShellAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    (void)application;
    (void)launchOptions;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[SelacoShellViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end

int main(int argc, char *argv[])
{
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(SelacoShellAppDelegate.class));
    }
}
