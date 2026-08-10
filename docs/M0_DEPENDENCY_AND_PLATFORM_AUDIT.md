# Milestone 0 Dependency and Platform Audit

Audit date: 2026-07-19

Source under review: `TheCockatrice/GZSelaco` at `7543afd533ea7c60ed61d2b6ad7518656d77097b`

MoltenVK package under review: `KhronosGroup/MoltenVK` release `v1.4.1`, iOS asset SHA-256 `54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701`

This document records verified source, build, platform, and licence observations. It does not claim that the full GZSelaco renderer or Selaco itself has launched on iOS.

## 1. Verified build characteristics

- The root project uses C++17.
- The build contains an explicit cross-compilation path and exports native executable targets for use by a target build.
- arm64 is recognized as an architecture.
- VM JIT is enabled by default only for x86_64, so arm64 naturally enters the interpreter path.
- Vulkan and GLES2 are independently configurable.
- The current upstream Apple configuration is macOS-oriented rather than iOS-aware.
- Native macOS host tools build successfully from the pinned source.
- A bounded source slice, including internal archive libraries, compiles for physical-device arm64 iPhoneOS.
- A bounded unsigned iPhoneOS app shell links against the pinned MoltenVK static library and Apple platform frameworks.
- Vulkan instance and Metal-surface creation paths compile and link into the arm64 device Mach-O.
- A static ZMusic 1.3.0 compatibility trial builds for arm64 iPhoneOS and satisfies the APIs consumed by GZSelaco.
- The ZMusic trial excludes bundled FluidSynth and macOS hardware CoreMIDI while retaining software MIDI backends.
- The libvpx version resolved by GZSelaco's vcpkg baseline builds as a decoder-only arm64 iPhoneOS static library.
- VP8 and VP9 decoder APIs link into an iPhoneOS contract while encoder interfaces remain excluded.

## 2. Dependency inventory

### Required or directly linked by the full engine

| Component | Source/build role | Current iOS disposition |
|---|---|---|
| SDL2 | Window, event, joystick, and platform backend when native Cocoa is disabled | Desktop SDL and Cocoa source sets are excluded by the bounded full-engine configure patch. A real UIKit/SDL iOS lifecycle and input layer remains unimplemented. |
| ZMusic | Required music and audio decoding library | Static arm64 iPhoneOS build and GZSelaco-facing API contract pass at trial commit `d3b730795784bff3f97571446101c57c1c6ac9bc`. Bundled FluidSynth and macOS hardware CoreMIDI are intentionally disabled. Physical audio playback remains unverified. |
| libvpx | Required VP8/VP9 video and animated-texture decoder | Decoder-only static arm64 iPhoneOS build and link contract pass at commit `03265cd42b3783532de72f2ded5436652e6f5ce3`, matching GZSelaco's vcpkg version `1.12.0` port `2`. Physical decoding remains unverified. |
| OpenAL / OpenAL Soft | Main sound backend unless disabled | Disabled in the current full-engine configure experiment. Static OpenAL Soft remains the preferred first audio-output direction; desktop dynamic loading is unsuitable. |
| BZip2 | Archive support | Native host and bounded arm64-iOS static builds pass. Full-engine linkage and notice packaging remain open. |
| LZMA | Internal archive library | Native host and bounded arm64-iOS static builds pass. Full-engine linkage and notice packaging remain open. |
| miniz | Internal archive library | Native host and bounded arm64-iOS static builds pass. Full-engine linkage and notice packaging remain open. |
| ZVulkan | Vulkan abstraction and renderer support | Full library not yet linked. Instance and `VK_EXT_metal_surface` boundaries are separately proven, and a dedicated iOS source-selection patch exists for the configure experiment. |
| MoltenVK | Vulkan-over-Metal runtime | Official iOS package pinned, hashed, inspected, and linked into the bounded shell. Physical execution remains unverified. |
| ZWidget | UI support library | Included by full-engine configuration but not independently compiled or linked for iOS. Platform assumptions remain under audit. |
| WebP | Internal image library | Included by full-engine configuration but not independently compiled or linked for iOS. |
| Discord RPC | Internal subproject linked by desktop engine configuration | Explicitly excluded from the bounded iOS full-engine configure path. |
| asmjit | Internal JIT library when VM JIT is enabled | Excluded by the arm64 JIT gate. |
| Apple frameworks | UIKit, Foundation, CoreGraphics, IOSurface, QuartzCore, Metal, MetalKit | Linked successfully in the bounded unsigned shell. |

### Native host tools

The build creates these tools as subprojects:

- `re2c`
- `lemon`
- `zipdir`

They must run as native macOS executables during an iOS cross-build. They must not be built for iPhone and then executed by the host.

The standalone host-tools project builds all three without configuring the desktop game. The probe also builds the bundled BZip2, LZMA, and miniz targets required by `zipdir`.

Verified run at reconciled branch head:

- Workflow: `Milestone 0 Host Tools Probe`
- Run: `29686759014`

## 3. Verified dependency probes

### ZMusic

- Workflow: `Milestone 0 ZMusic iOS Probe`
- Run: `29687858702`
- Static/API artifact: `8442657394`
- Artifact digest: `sha256:645987ebd7d4a0d35c62c90a433ef177bee6a603ea8a71f779f4b887c6de0998`
- Evidence artifact: `8442657216`
- Evidence digest: `sha256:0bc361ebe1d48acf157714c48d7224ed3c2a5bd8dd1a0ff5b2ae3f53c8166d0c`

See `docs/M0_ZMUSIC_IOS_PROBE.md`.

### libvpx

- Workflow: `Milestone 0 libvpx iOS Probe`
- Run: `29688440311`
- Decoder library/headers/contract artifact: `8442811842`
- Artifact digest: `sha256:dc2f735cb91dae44f0a468ad749f30372f1a638e0da032d5b6f487b969d801d9`
- Evidence artifact: `8442811755`
- Evidence digest: `sha256:9fdc01e4a85ebdd85e74579b3b95bda9ef4ff64c2e519eb61426831112e612a6`

See `docs/M0_LIBVPX_IOS_PROBE.md`.

## 4. Licence status

This section records source facts and packaging work still required. It is not a legal opinion.

| Component or boundary | Verified licence fact | Distribution action still required |
|---|---|---|
| GZSelaco | Root `LICENSE` contains GNU GPL version 3. | Preserve notices, publish corresponding source and build scripts when conveying a covered binary, and mark modifications. |
| MoltenVK v1.4.1 | Root and release-package `LICENSE` contain Apache License 2.0. | Preserve the Apache licence and applicable attribution/NOTICE material. Audit embedded external-library notices in the static archive. |
| MoltenVK external dependencies | Upstream identifies cereal, SPIRV-Cross, SPIRV-Headers, SPIRV-Tools, volk, Vulkan-Headers, and Vulkan-Tools as external projects; volk and Vulkan-Tools are demo-only according to upstream. | Determine which external components are actually incorporated into the shipped iOS static archive and preserve each required notice. |
| SelacoiOS original integration code | Repository currently has no explicit root licence for original files. | Add an explicit licence compatible with the intended GZSelaco integration before any public or third-party binary/source distribution. |
| Apple frameworks | Linked as operating-system frameworks and not copied into the repository. | No framework binary is redistributed by this project; normal Apple SDK and platform terms still apply. |
| Proprietary Selaco data | Explicitly excluded from Git, CI, and build artifacts. | Continue requiring user-supplied legally obtained data at runtime. |
| ZMusic and its bundled synthesizer/decoder sources | Exact trial revision is pinned and builds, but the complete per-component notice bundle is not yet assembled. | Inventory every compiled third-party backend, preserve required licence texts, and document disabled FluidSynth/CoreMIDI paths. |
| libvpx | Exact revision and GZSelaco vcpkg mapping are pinned and the decoder-only build passes. | Preserve libvpx's licence and source/build correspondence for the linked configuration. |
| OpenAL Soft, SDL2, WebP, archive libraries, ZWidget | Exact final revisions and notice set are not yet closed for the proposed full iOS binary. | Pin each included revision, record licence files, and generate a reproducible third-party-notices bundle before distribution work. |

Current licence classification:

- **Private source experimentation:** permitted subject to the underlying licences and without conveying proprietary Selaco data.
- **Public source release:** not yet ready because the SelacoiOS original-code licence and complete third-party notice set are not closed.
- **Binary distribution:** not authorized by Milestone 0 and not licence-ready.

## 5. Verified Apple-platform conflicts

### 5.1 Apple currently means macOS

The root build sets a macOS deployment target whenever `APPLE` is true. CMake also reports `APPLE` for iOS toolchains, so this condition is too broad for a correct iPhone target.

The bounded source-selection patch now guards the desktop deployment target from iOS while preserving macOS behaviour.

### 5.2 Cocoa and desktop SDL source selection

Upstream defaults to a desktop Cocoa backend for Apple builds. Falling back from Cocoa selects desktop SDL sources rather than a genuine iOS layer.

The bounded configure patch:

- excludes the macOS Cocoa entry point;
- excludes the desktop SDL source set;
- introduces a dedicated iOS source-selection marker and platform stub;
- preserves all desktop branches unchanged outside the experimental checkout.

The stub is configuration evidence only. It is not a lifecycle, input, filesystem, or rendering implementation.

### 5.3 Desktop Apple audio paths

The existing OpenAL path adds desktop-oriented Apple frameworks including `ApplicationServices`. ZMusic also contained desktop-specific FluidSynth/GLib and hardware CoreMIDI assumptions.

Current bounded decisions:

- disable OpenAL during full-engine configure;
- disable bundled FluidSynth for the first ZMusic iOS trial;
- exclude the macOS hardware CoreMIDI backend;
- retain software MIDI synthesis;
- evaluate static OpenAL Soft separately before audio-output linkage.

### 5.4 Vulkan surface selection lacks iOS upstream

The current upstream surface builder selects Win32, obsolete macOS MVK, or Xlib platform extensions. It does not select `VK_EXT_metal_surface`.

The bounded SelacoiOS shell proves that a correct iOS path can compile and link with:

- `VK_USE_PLATFORM_METAL_EXT`;
- `VK_KHR_surface`;
- `VK_EXT_metal_surface`;
- a `CAMetalLayer` supplied by an iOS view;
- `vkCreateMetalSurfaceEXT` and `vkDestroySurfaceKHR`.

See `docs/M0_VULKAN_COMPATIBILITY_INVENTORY.md`.

## 6. Initial target policy

The first full-engine configure and compile experiments must retain these decisions:

- `HAVE_VM_JIT=OFF`
- `FORCE_INTERNAL_BZIP2=ON`
- `NO_OPENAL=ON` until a static OpenAL Soft gate exists
- `SEND_ANON_STATS=OFF`
- Discord RPC excluded
- no GTK
- no Steam integration
- no desktop Cocoa entry point
- no desktop SDL source set presented as iOS support
- `VK_EXT_metal_surface` for presentation
- pinned static ZMusic without FluidSynth or hardware CoreMIDI
- pinned decoder-only static libvpx
- no signing or IPA packaging
- no proprietary Selaco data
- controller and touch implementation out of scope

## 7. Remaining evidence questions

1. Can the full GZSelaco project complete CMake configuration while consuming the pinned host tools, ZMusic, libvpx, and MoltenVK inputs?
2. What is the first full-engine translation-unit failure after configuration succeeds?
3. Can ZWidget, WebP, ZVulkan, and the portable engine source set compile cleanly for arm64 iOS?
4. Which portable POSIX files can be reused without desktop APIs?
5. Do the A18 Pro Vulkan feature bits and queue topology satisfy GZSelaco's required device filter?
6. Does the BC1/BC3/BC7 compressed texture path work unchanged through MoltenVK?
7. Does the interpreted VM sustain acceptable frame time in a representative combat scene?
8. Which third-party source and notice files are incorporated into the final linked binary?

## 8. Next bounded experiment

Complete the full-engine CMake configure probe that:

1. fetches the exact GZSelaco, ZMusic, libvpx, and MoltenVK pins;
2. consumes the verified native host tools;
3. applies the explicit iOS source-selection patch without deleting or rewriting desktop branches;
4. excludes desktop Cocoa, desktop SDL, GTK, Steam, Discord RPC, JIT, dynamic audio paths, and proprietary data;
5. requires GZSelaco to discover the pinned arm64 ZMusic and libvpx libraries;
6. stops at the first unclassified configuration boundary;
7. archives the exact cache, source selection, command line, and failure evidence;
8. does not compile, link, package, sign, install, or load commercial game data.

Passing configuration authorizes only a separately bounded first full-engine compile experiment.
