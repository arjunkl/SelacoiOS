# Milestone 2 Swapchain Clear-Frame Physical Test

## Purpose

This is a bounded physical-device validation of Vulkan logical-device, swapchain, image acquisition, command submission, clear rendering, and FIFO presentation through an iOS `CAMetalLayer`.

It does not load `Selaco.ipk3` and does not enter the GZSelaco game loop.

## Canonical build

- Workflow: `Milestone 2 Swapchain Clear Frame`
- Run: `29703600142`
- Branch head tested by CI: `d958a6fa90c170586f50a4dd0a83fc09d8b385a4`
- Bundle identifier: `am.arjunkl.selacoios.swapchain.m2`
- Version/build: `0.4.0 (4)`
- Architecture: arm64
- Minimum iOS: 15.0
- Renderer: Vulkan through embedded dynamic MoltenVK
- Signing state: unsigned

### IPA artifact

- Artifact name: `selaco-m2-swapchain-clear-frame-unsigned-ipa`
- Artifact ID: `8447242258`
- GitHub artifact digest: `sha256:72730f9646a610194d63119e69095fb1acd712544fda670a76e98622a89f1725`
- GitHub artifact size: `8,449,518` bytes
- Expires: 2026-08-02

### Inner IPA

- File: `Selaco-swapchain-clear-frame-unsigned.ipa`
- SHA-256: `e41db84c0ecec88982442b8350d31ee2cfc529d80820f9a5f63e065bf7e7a37c`
- Size: `8,467,452` bytes

## CI-verified contents

The IPA contains:

- `Payload/Selaco.app/Selaco`
- `Payload/Selaco.app/Info.plist`
- `Payload/Selaco.app/Frameworks/MoltenVK.framework/MoltenVK`

CI verified:

- complete selected GZSelaco translation-unit compilation;
- successful final arm64 iPhoneOS linkage;
- iOS 15.0 deployment target;
- embedded dynamic MoltenVK linkage through `@rpath/MoltenVK.framework/MoltenVK`;
- UIKit entry point retention;
- `vkCreateSwapchainKHR` and `vkQueuePresentKHR` retention;
- clear-frame command recording code retention;
- successful app-bundle validation;
- valid unsigned IPA structure with no provisioning profile or private signing material.

## Expected physical result

After signing and installing, the app should show a blue Vulkan-presented background with a UIKit diagnostic overlay. The overlay should report:

- UIKit lifecycle: PASS
- Metal layer: PASS
- physical device: Apple A18 Pro GPU
- swapchain: PASS
- selected color format
- drawable extent
- swapchain image count
- present mode: FIFO
- graphics/present queue family
- continuously increasing frame count
- last `VkResult`

A successful result should reach at least 300 presented frames without crashing or freezing.

## Lifecycle checks

After presentation is stable:

1. Send the app to the background and return to it.
2. Confirm presentation resumes and the frame counter continues.
3. Rotate or otherwise trigger a drawable-size/layout change if the device permits it.
4. Confirm the swapchain recreates and presentation continues.

## Persistent evidence

The app writes:

- `Documents/Selaco/runtime-bootstrap.txt`
- `Documents/Selaco/swapchain-status.txt`

With Files sharing enabled, these should be available under the app's folder in **Files → On My iPhone**.

## Stop condition

Stop after collecting the screen result, frame count, lifecycle behavior, and persistent files. Do not import `Selaco.ipk3` or treat a successful clear frame as authorization to enter the engine loop.
