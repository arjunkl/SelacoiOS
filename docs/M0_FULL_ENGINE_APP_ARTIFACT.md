# Milestone 0 Full-Engine iPhoneOS App Artifact

Evidence date: 2026-07-19

## Scope

This document records the successful Milestone 0 compilation, linkage, bundle creation, and static validation of the complete pinned GZSelaco engine for physical-device arm64 iPhoneOS.

It does not claim that the app has launched on a physical device, initialized the complete renderer at runtime, loaded Selaco game data, reached a menu, or executed gameplay.

## Pinned inputs

- GZSelaco: `TheCockatrice/GZSelaco` at `7543afd533ea7c60ed61d2b6ad7518656d77097b`
- MoltenVK: official `v1.4.1` iOS release package
- ZMusic compatibility trial: `ZDoom/ZMusic` at `d3b730795784bff3f97571446101c57c1c6ac9bc`
- libvpx: `webmproject/libvpx` at `03265cd42b3783532de72f2ded5436652e6f5ce3`
- Target: physical arm64 iPhoneOS, minimum iOS 15.0
- Renderer selection: Vulkan only through statically linked MoltenVK

## Verified result

Workflow `Milestone 0 Full Engine App Artifact`, run `29693226742`, completed successfully at branch head `f122fe099c155cd159e3ccea569b9d725cfeafb4`.

The workflow reproduced the complete dependency and engine build, linked the full GZSelaco target, ran its post-build resource rules, preserved `Selaco.app`, and validated the resulting bundle.

Verified properties:

- complete selected GZSelaco translation-unit compilation passed;
- full application linkage passed;
- Xcode bundle validation passed;
- executable is Mach-O arm64 only;
- executable is marked for platform iOS;
- minimum operating-system version is iOS 15.0;
- SDK recorded by the linker is iPhoneOS 18.5;
- dynamic dependencies are restricted to Apple frameworks and system libraries;
- the application is unsigned;
- no proprietary Selaco game data is present;
- desktop Cocoa, desktop SDL, desktop OpenGL, Discord RPC, VM JIT, dynamic OpenAL, FluidSynth, and hardware CoreMIDI are excluded from this first iOS target.

## Preserved artifacts

### Unsigned app artifact

- GitHub Actions artifact: `selaco-m0-full-engine-unsigned-app`
- Artifact ID: `8444277297`
- GitHub artifact digest: `sha256:4732463d7ad3adea0f79176b165970eeab36366cb9c1f1718f95fe2722aec4c0`
- GitHub artifact size: `7,037,433` bytes
- Expiration: 2026-08-02

The GitHub artifact contains the project-generated archive below.

### Project-generated app archive

- File: `Selaco-full-engine-unsigned-app.zip`
- SHA-256: `9d6aaecfd6b075fded25dd2ee3de03e6f651f357cf6762e4abcf366de673400b`
- Size: `7,051,239` bytes

### Evidence artifact

- GitHub Actions artifact: `selaco-m0-full-engine-app-evidence`
- Artifact ID: `8444277001`
- GitHub artifact digest: `sha256:ef953658e404906da63611a107ead0bdb8aa60fc3b262d8c9c75f2e49ebcae93`
- GitHub artifact size: `260,716` bytes
- Expiration: 2026-08-02

## Current runtime limitation

The bounded iOS process entry currently initializes command-line ownership and timing calibration, then exits successfully. This is intentional for the Milestone 0 link closure.

The preserved application therefore proves full engine compilation, linkage, bundle structure, and Apple-platform dependency closure. It is not yet a runnable Selaco experience.

## Next authorized boundary

The next bounded milestone is a physical-runtime bootstrap that:

1. replaces the terminating process stub with a UIKit application lifecycle;
2. passes an iOS-owned `CAMetalLayer` into the engine platform layer;
3. creates and destroys the Vulkan instance and Metal surface on a physical A18 Pro device;
4. records structured logs and a visible status screen;
5. does not yet import or bundle `Selaco.ipk3`;
6. stops before swapchain presentation, menu startup, audio, input, saves, or gameplay unless separately authorized by a later gate.
