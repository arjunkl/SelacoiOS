# SelacoiOS

SelacoiOS is an experimental, community-driven effort to investigate and build a native iOS port of the open-source GZSelaco engine for use with a legally obtained copy of **Selaco**.

## Current status

The project has completed its principal **Milestone 0 compile, link, and bundle-feasibility gates** and is entering bounded physical-runtime bootstrap work.

Verified so far:

- exact GZSelaco source pin and proprietary-asset boundary;
- native macOS host tools;
- official MoltenVK iOS package pin and SHA-256 verification;
- a static arm64 iPhoneOS ZMusic compatibility build and GZSelaco-facing API contract, with desktop-only FluidSynth and hardware CoreMIDI paths explicitly excluded;
- a decoder-only static arm64 iPhoneOS libvpx build with VP8/VP9 decoder symbols and an iOS link contract, while encoder code remains excluded;
- a dedicated iOS platform source set with desktop Cocoa, desktop SDL, Discord RPC, VM JIT, dynamic OpenAL, and desktop OpenGL excluded;
- a native iOS framebuffer contract and bounded sandbox-path, timing, console, and process runtime closure;
- Vulkan-only compilation of the complete selected GZSelaco translation-unit graph for physical-device arm64 iPhoneOS;
- successful full application linkage against pinned static MoltenVK, ZMusic, libvpx, and internal engine libraries;
- a preserved unsigned `Selaco.app` with valid iPhoneOS bundle metadata, arm64-only Mach-O output, minimum iOS 15.0, and only Apple/system dynamic dependencies.

Not yet verified:

- physical-device launch or execution;
- a live UIKit lifecycle for the full-engine application;
- Vulkan instance or Metal-surface creation by the full engine on A18 Pro;
- swapchain creation or frame presentation;
- Selaco game-data import;
- menu startup, controls, audio output, movie playback, animated VPX textures, saves, scripting behaviour, gameplay, or performance;
- signing, IPA installation, TestFlight, App Store, or public distribution readiness.

The active engine and renderer pins are recorded in [`SOURCE_PIN.env`](SOURCE_PIN.env) and [`MOLTENVK_PIN.env`](MOLTENVK_PIN.env). Explicit dependency compatibility trials are recorded separately in [`DEPENDENCY_TRIAL_PINS.env`](DEPENDENCY_TRIAL_PINS.env).

## Legal and asset boundary

This repository must not contain Selaco's proprietary game data, including `Selaco.ipk3`, commercial artwork, audio, maps, videos, or other assets extracted from a purchased installation.

The intended eventual workflow is an engine-only iOS application that imports game data supplied by the user from their own legally obtained copy. Engine source and modifications will be handled under the applicable open-source licences. Selaco names and trademarks remain the property of their respective owners.

This project is not affiliated with or endorsed by Altered Orbit Studios, Fulqrum Publishing, the GZDoom team, or Apple.

## Initial technical direction

- Target: physical arm64 iPhone, initially an iPhone 16 Pro Max / A18 Pro
- Renderer: Vulkan through MoltenVK
- Surface: `VK_EXT_metal_surface` over an iOS-owned `CAMetalLayer`
- Input: external controller first; touch and gyro after engine viability is proven
- Data: user-imported `Selaco.ipk3`; never committed or bundled
- Distribution: no public-release assumptions; current work does not authorize signed packaging or installation

## Project evidence

- [`docs/PROJECT_COMMAND_CENTRE.md`](docs/PROJECT_COMMAND_CENTRE.md): scope, verified evidence, milestone gates, and stop conditions
- [`docs/M0_DEPENDENCY_AND_PLATFORM_AUDIT.md`](docs/M0_DEPENDENCY_AND_PLATFORM_AUDIT.md): dependency, platform, and licence status
- [`docs/M0_VULKAN_COMPATIBILITY_INVENTORY.md`](docs/M0_VULKAN_COMPATIBILITY_INVENTORY.md): GZSelaco requirements compared with MoltenVK v1.4.1
- [`docs/M0_ZMUSIC_IOS_PROBE.md`](docs/M0_ZMUSIC_IOS_PROBE.md): successful static ZMusic iPhoneOS trial, adaptations, limitations, and evidence
- [`docs/M0_LIBVPX_IOS_PROBE.md`](docs/M0_LIBVPX_IOS_PROBE.md): successful decoder-only libvpx iPhoneOS trial and evidence
- [`docs/M0_FULL_ENGINE_APP_ARTIFACT.md`](docs/M0_FULL_ENGINE_APP_ARTIFACT.md): successful complete engine compile, link, bundle validation, and unsigned app artifact evidence

Development proceeds through evidence-gated milestones rather than broad speculative implementation.
