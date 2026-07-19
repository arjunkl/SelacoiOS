# Milestone 0 Dependency and Platform Audit

Audit date: 2026-07-19

Source under review: `TheCockatrice/GZSelaco` at `7543afd533ea7c60ed1d2b6ad7518656d77097b`

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

## 2. Dependency inventory

### Required or directly linked by the full engine

| Component | Source/build role | Current iOS disposition |
|---|---|---|
| SDL2 | Window, event, joystick, and platform backend when native Cocoa is disabled | Not integrated. Requires a deliberate SDL iOS or custom UIKit source branch. Desktop SDL source selection is not acceptable proof. |
| ZMusic | Required music and audio decoding library | Not yet pinned or cross-compiled. Exact revision, codec closure, and licence notices remain open. |
| libvpx | Required video codec; configuration errors when absent | Not yet cross-compiled. Video cannot be silently dropped without an explicit product decision. |
| OpenAL / OpenAL Soft | Main sound backend unless disabled | Not yet integrated. Static OpenAL Soft remains the preferred direction; desktop dynamic loading is unsuitable. |
| BZip2 | Archive support | Native host and bounded arm64-iOS static builds pass. Full-engine linkage and notice packaging remain open. |
| LZMA | Internal archive library | Native host and bounded arm64-iOS static builds pass. Full-engine linkage and notice packaging remain open. |
| miniz | Internal archive library | Native host and bounded arm64-iOS static builds pass. Full-engine linkage and notice packaging remain open. |
| ZVulkan | Vulkan abstraction and renderer support | Full library not yet linked. Instance and `VK_EXT_metal_surface` boundary is separately proven. |
| MoltenVK | Vulkan-over-Metal runtime | Official iOS package pinned, hashed, inspected, and linked into the bounded shell. Physical execution remains unverified. |
| ZWidget | UI support library | Not yet compiled for iOS. Platform assumptions require audit. |
| WebP | Internal image library | Not yet cross-compiled in the target build. |
| Discord RPC | Internal subproject linked by desktop engine configuration | Must be disabled or excluded from the first iOS target. |
| asmjit | Internal JIT library when VM JIT is enabled | Must remain excluded on arm64 iOS. |
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

## 3. Licence status

This section records source facts and packaging work still required. It is not a legal opinion.

| Component or boundary | Verified licence fact | Distribution action still required |
|---|---|---|
| GZSelaco | Root `LICENSE` contains GNU GPL version 3. | Preserve notices, publish corresponding source and build scripts when conveying a covered binary, and mark modifications. |
| MoltenVK v1.4.1 | Root and release-package `LICENSE` contain Apache License 2.0. | Preserve the Apache licence and applicable attribution/NOTICE material. Audit embedded external-library notices in the static archive. |
| MoltenVK external dependencies | Upstream identifies cereal, SPIRV-Cross, SPIRV-Headers, SPIRV-Tools, volk, Vulkan-Headers, and Vulkan-Tools as external projects; volk and Vulkan-Tools are demo-only according to upstream. | Determine which external components are actually incorporated into the shipped iOS static archive and preserve each required notice. |
| SelacoiOS original integration code | Repository currently has no explicit root licence for original files. | Add an explicit licence compatible with the intended GZSelaco integration before any public or third-party binary/source distribution. |
| Apple frameworks | Linked as operating-system frameworks and not copied into the repository. | No framework binary is redistributed by this project; normal Apple SDK and platform terms still apply. |
| Proprietary Selaco data | Explicitly excluded from Git, CI, and build artifacts. | Continue requiring user-supplied legally obtained data at runtime. |
| ZMusic, libvpx, OpenAL Soft, SDL2, WebP, archive libraries, ZWidget, Discord RPC | Exact revisions and notice set are not yet closed for the proposed full iOS binary. | Pin each included revision, record its licence files, and generate a reproducible third-party-notices bundle before distribution work. |

Current licence classification:

- **Private source experimentation:** permitted subject to the underlying licences and without conveying proprietary Selaco data.
- **Public source release:** not yet ready because the SelacoiOS original-code licence and complete third-party notice set are not closed.
- **Binary distribution:** not authorized by Milestone 0 and not licence-ready.

## 4. Verified Apple-platform conflicts

### 4.1 Apple currently means macOS

The root build sets a macOS deployment target whenever `APPLE` is true. CMake also reports `APPLE` for iOS toolchains, so this condition is too broad for a correct iPhone target.

Required bounded change:

- introduce an explicit iOS platform test before applying macOS deployment settings;
- keep macOS behaviour unchanged;
- set iOS deployment through the iOS toolchain or Xcode target rather than the desktop branch.

### 4.2 Cocoa backend defaults on

The source declares `OSX_COCOA_BACKEND` and defaults it to `ON` for Apple builds. The Apple source selection then chooses desktop Cocoa files such as macOS main, video, console, and system implementations.

Required bounded change:

- add a dedicated iOS platform source set;
- do not compile the macOS Cocoa entry point or desktop windowing implementation for iPhone;
- evaluate reuse of portable POSIX code separately from UIKit/SDL lifecycle code.

Simply setting `OSX_COCOA_BACKEND=OFF` is not sufficient because the fallback source set is desktop SDL-oriented and includes crash handling and window assumptions that still require review.

### 4.3 Desktop Apple audio frameworks are selected

The existing OpenAL path adds desktop-oriented Apple frameworks including `ApplicationServices`.

Required bounded change:

- use static OpenAL Soft for the initial target;
- link only iOS-available audio frameworks required by that configuration;
- prohibit runtime loading of an arbitrary OpenAL dynamic library.

### 4.4 No dedicated iOS platform directory exists

The pinned source contains no dedicated iOS or iPhone platform layer. Successful macOS support must not be represented as iOS support.

### 4.5 Vulkan surface selection lacks iOS

The current surface builder selects Win32, obsolete macOS MVK, or Xlib platform extensions. It does not select `VK_EXT_metal_surface`.

The bounded SelacoiOS shell now proves that a correct iOS path can compile and link with:

- `VK_USE_PLATFORM_METAL_EXT`;
- `VK_KHR_surface`;
- `VK_EXT_metal_surface`;
- a `CAMetalLayer` supplied by an iOS view;
- `vkCreateMetalSurfaceEXT` and `vkDestroySurfaceKHR`.

See `docs/M0_VULKAN_COMPATIBILITY_INVENTORY.md`.

## 5. Initial target policy

The first full-engine configure experiment must retain these decisions:

- `HAVE_VM_JIT=OFF`
- `FORCE_INTERNAL_BZIP2=ON`
- `DYN_OPENAL=OFF`
- `SEND_ANON_STATS=OFF`
- disable or omit Discord RPC
- no GTK
- no Steam integration
- no desktop Cocoa entry point
- no desktop SDL source set presented as iOS support
- `VK_EXT_metal_surface` for presentation
- no signing or IPA packaging
- no proprietary Selaco data
- controller and touch implementation out of scope

## 6. Remaining evidence questions

1. Which exact ZMusic revision and codec dependencies are expected by the pinned engine?
2. Can libvpx, ZMusic, OpenAL Soft, ZWidget, WebP, and the selected platform layer compile cleanly for arm64 iOS?
3. Which portable POSIX files can be reused without desktop APIs?
4. Do the A18 Pro Vulkan feature bits and queue topology satisfy GZSelaco's required device filter?
5. Does the BC1/BC3/BC7 compressed texture path work unchanged through MoltenVK?
6. Does the interpreted VM sustain acceptable frame time in a representative combat scene?
7. Can the verified native host executables be imported cleanly into the full target CMake build?
8. Which third-party source and notice files are incorporated into the final linked binary?

## 7. Next bounded experiment

Prepare a full-engine CMake source-selection probe that:

1. fetches the exact GZSelaco and MoltenVK pins;
2. consumes the verified native host tools;
3. introduces an explicit iOS platform branch without deleting or rewriting desktop branches;
4. excludes desktop Cocoa, GTK, Steam, Discord RPC, JIT, and dynamic OpenAL paths;
5. compiles only until the first classified full-engine translation-unit or dependency boundary;
6. archives the exact cache, source selection, command line, and first failure;
7. does not package, sign, install, or load proprietary game data.

Passing that experiment authorizes only the next classified compile or link boundary.
