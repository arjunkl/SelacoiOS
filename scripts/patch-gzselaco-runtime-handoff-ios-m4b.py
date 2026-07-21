#!/usr/bin/env python3
"""Coordinate UIKit diagnostic teardown and the real engine renderer handoff."""

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
        print("usage: patch-gzselaco-runtime-handoff-ios-m4b.py <GZSelaco source>", file=sys.stderr)
        return 2
    runtime = pathlib.Path(sys.argv[1]).resolve() / "src" / "common" / "platform" / "ios" / "i_platform_runtime.mm"
    if not runtime.is_file():
        raise RuntimeError(f"Milestone 4B runtime prerequisite is missing: {runtime}")

    replace_once(
        runtime,
        'extern "C" const char *SelacoIOSM4RendererStrategy();\n',
        'extern "C" const char *SelacoIOSM4RendererStrategy();\n'
        'extern "C" void SelacoIOSRegisterEngineMetalLayer(CAMetalLayer *layer);\n'
        'extern "C" bool SelacoIOSPrepareEngineRendererHandoff();\n',
        "declare the renderer handoff bridge",
    )
    replace_once(
        runtime,
        """            "-nosound",
            "-nomusic",
        };
""",
        """            "-nosound",
            "-nomusic",
            "-nointro",
            "+gl_texture_thread",
            "0",
            "+vk_max_transfer_threads",
            "0",
            "+vid_vsync",
            "1",
        };
""",
        "select narrow renderer/title startup arguments",
    )
    replace_once(
        runtime,
        """        SelacoIOSReportLicensedAssetProbe(
            "renderer_strategy_selected",
            SelacoIOSM4RendererStrategy());
        SelacoIOSReportLicensedAssetProbe(
            "engine_probe_starting",
            "Calling the real GZSelaco GameMain through early initialization and stopping before V_Init2");
""",
        """        SelacoIOSReportLicensedAssetProbe(
            "renderer_strategy_selected",
            SelacoIOSM4RendererStrategy());
        SelacoIOSReportLicensedAssetProbe(
            "renderer_handoff_requested",
            "pausing CADisplayLink and destroying diagnostic Vulkan ownership");
        if (!SelacoIOSPrepareEngineRendererHandoff()) {
            SelacoIOSReportLicensedAssetProbe(
                "renderer_handoff_failed",
                "UIKit controller could not release diagnostic Vulkan ownership");
            return;
        }
        SelacoIOSReportLicensedAssetProbe(
            "renderer_handoff_passed",
            "diagnostic instance, device, surface, swapchain, and Volk state destroyed");
        SelacoIOSReportLicensedAssetProbe(
            "engine_probe_starting",
            "Calling real GZSelaco through renderer initialization and title/menu startup");
""",
        "perform the diagnostic-to-engine handoff",
    )
    replace_once(
        runtime,
        '    if ([phaseText containsString:@"renderer"] || [phaseText containsString:@"v_init2"]) {\n',
        """    if ([phaseText containsString:@"renderer"] ||
        [phaseText containsString:@"v_init2"] ||
        [phaseText containsString:@"engine_vulkan"] ||
        [phaseText containsString:@"engine_metal"] ||
        [phaseText containsString:@"engine_volk"] ||
        [phaseText containsString:@"engine_instance"] ||
        [phaseText containsString:@"engine_render"] ||
        [phaseText containsString:@"engine_first_frame"]) {
""",
        "persist all renderer phases",
    )
    replace_once(
        runtime,
        """@property(nonatomic, strong) NSString *assetStatusText;
@end

@implementation SelacoSwapchainViewController
""",
        """@property(nonatomic, strong) NSString *assetStatusText;
- (BOOL)prepareEngineRendererHandoff;
@end

static SelacoSwapchainViewController *gRendererHandoffController = nil;

@implementation SelacoSwapchainViewController
""",
        "declare the active handoff controller without ARC-only weak storage",
    )
    replace_once(
        runtime,
        '    self.initializationStarted = YES;\n    WriteBreadcrumb(@"phase=m2_uikit_visible");\n',
        '    self.initializationStarted = YES;\n'
        '    gRendererHandoffController = self;\n'
        '    WriteBreadcrumb(@"phase=m2_uikit_visible");\n',
        "register the active handoff controller",
    )
    replace_once(
        runtime,
        """- (void)licensedAssetProbeStatus:(NSNotification *)notification
{
    NSString *text = notification.userInfo[@"text"];
    if (text.length > 0) {
        self.assetStatusText = text;
        if (_presenter) {
            NSString *combined = [self combinedStatusText:_presenter->Status()];
            self.statusLabel.text = combined;
            WriteStatusSnapshot(combined);
        }
    }
}

""",
        """- (void)licensedAssetProbeStatus:(NSNotification *)notification
{
    NSString *text = notification.userInfo[@"text"];
    if (text.length > 0) {
        self.assetStatusText = text;
        if (_presenter) {
            NSString *combined = [self combinedStatusText:_presenter->Status()];
            self.statusLabel.text = combined;
            WriteStatusSnapshot(combined);
        } else {
            self.statusLabel.text = text;
        }
        if ([text containsString:@"phase=m4_engine_first_frame_presented"]) {
            self.statusLabel.hidden = YES;
        }
    }
}

""",
        "continue UI status reporting after teardown",
    )

    handoff_method = """- (BOOL)prepareEngineRendererHandoff
{
    WriteBreadcrumb(@"phase=m4_renderer_handoff_main_thread_entered");
    self.displayLink.paused = YES;
    [self.displayLink invalidate];
    self.displayLink = nil;
    if (_presenter) {
        _presenter->Pause();
        _presenter.reset();
    }
    if (self.metalLayer == nil || self.metalLayer.device == nil) {
        WriteBreadcrumb(@"phase=m4_renderer_handoff_layer_missing");
        return NO;
    }
    SelacoIOSRegisterEngineMetalLayer(self.metalLayer);
    self.statusLabel.hidden = NO;
    self.statusLabel.text =
        @"SelacoiOS Engine Init\n\n"
         "Diagnostic Vulkan: released\n"
         "Starting GZSelaco renderer…";
    WriteBreadcrumb(@"phase=m4_renderer_handoff_main_thread_passed");
    return YES;
}

"""
    replace_once(
        runtime,
        '- (void)renderFrame:(CADisplayLink *)displayLink\n',
        handoff_method + '- (void)renderFrame:(CADisplayLink *)displayLink\n',
        "add the main-thread Vulkan teardown",
    )

    bridge = """extern "C" bool SelacoIOSPrepareEngineRendererHandoff()
{
    __block BOOL success = NO;
    void (^handoff)(void) = ^{
        if (gRendererHandoffController != nil) {
            success = [gRendererHandoffController prepareEngineRendererHandoff];
        }
    };
    if (NSThread.isMainThread) handoff();
    else dispatch_sync(dispatch_get_main_queue(), handoff);
    return success == YES;
}

"""
    replace_once(
        runtime,
        '@end\n\n@interface SelacoSwapchainAppDelegate : UIResponder <UIApplicationDelegate>\n',
        '@end\n\n' + bridge
        + '@interface SelacoSwapchainAppDelegate : UIResponder <UIApplicationDelegate>\n',
        "expose the synchronous renderer handoff bridge",
    )
    replace_once(
        runtime,
        '    self.displayLink = nil;\n    _presenter.reset();\n}\n',
        '    self.displayLink = nil;\n'
        '    _presenter.reset();\n'
        '    if (gRendererHandoffController == self) {\n'
        '        gRendererHandoffController = nil;\n'
        '    }\n'
        '}\n',
        "clear the handoff controller during teardown",
    )

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        raise SystemExit(1)
