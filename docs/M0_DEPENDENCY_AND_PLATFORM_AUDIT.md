# Milestone 0 Dependency and Platform Audit

Audit date: 2026-07-19

Source under review: `TheCockatrice/GZSelaco` at `7543afd533ea7c60ed61d2b6ad7518656d77097b`

This document records verified source observations and bounded engineering implications. Native macOS host-tool evidence is recorded below, but no dependency or engine target is claimed to have compiled, linked, launched, or run correctly on iOS.

## 1. Verified build characteristics

- The root project uses C++17.
- The build contains an explicit cross-compilation path and exports native executable targets for use by a target build.
- arm64 is recognized as an architecture.
- VM JIT is enabled by default only for x86_64, so arm64 naturally enters the interpreter path.
- Vulkan and GLES2 are independently configurable.
- The current Apple configuration is macOS-oriented rather than iOS-aware.

## 2. Verified dependency inventory

### Required or directly linked by the engine

| Component | Source/build role | Initial iOS disposition |
|---|---|---|
| SDL2 | Window, event, joystick, and platform backend when native Cocoa is disabled | Likely usable, but requires the SDL iOS backend and an iOS-specific source selection branch |
| ZMusic | Required music and audio decoding library | Must be cross-compiled and licence-audited |
| libvpx | Required video codec; configuration errors when absent | Must be cross-compiled or video support must be deliberately refactored |
| OpenAL / OpenAL Soft | Main sound backend unless disabled | Prefer static OpenAL Soft; dynamic loading is unsuitable as the initial iOS path |
| BZip2 | Archive support | Native macOS bundled target passed; arm64-iOS cross-compile remains unverified |
| LZMA | Internal library | Native macOS bundled target passed; arm64-iOS cross-compile remains unverified |
| miniz | Internal library | Native macOS bundled target passed; arm64-iOS cross-compile remains unverified |
| ZVulkan | Vulkan abstraction and renderer support | Required for the MoltenVK direction; feature audit required |
| ZWidget | UI support library | Compile and platform audit required |
| WebP | Internal image library | Cross-compile audit required |
| Discord RPC | Added as an internal subproject and linked by the engine | Disable or exclude for the first iOS target |
| asmjit | Internal JIT library when VM JIT is enabled | Must remain excluded on arm64 iOS |

### Native host tools

The build creates these tools as subprojects:

- `re2c`
- `lemon`
- `zipdir`

The engine uses generated parser/scanner outputs and PK3 construction steps. These tools must run as native macOS executables during an iOS cross-build. They must not be built for iPhone and then executed by the host.

A standalone native-host project now builds these tools without configuring the desktop game. Workflow run `29685158509` passed on macOS 15.7.7 arm64 and preserved:

- configure and build logs;
- CMake cache;
- compile commands;
- executable paths and SHA-256 hashes;
- the `re2c` version output;
- a machine-readable `PASS` marker.

Evidence artifact: `8441834895`, digest `sha256:f73f8e1f09d72dc67e00e0218330269f19452d83bb5c36f0d9eabc40e51369c9`.

This verifies only native host execution. It does not verify imported executable targets inside an iOS cross-build yet.

## 3. Verified Apple-platform conflicts

### 3.1 Apple currently means macOS

The root build sets a macOS deployment target of 10.13 whenever `APPLE` is true. CMake also reports `APPLE` for iOS toolchains, so this condition is too broad for a correct iPhone target.

Required bounded change:

- introduce an explicit iOS platform test before applying macOS deployment settings;
- keep macOS behaviour unchanged;
- set iOS deployment through the iOS toolchain or Xcode target rather than the desktop branch.

### 3.2 Cocoa backend defaults on

The source declares `OSX_COCOA_BACKEND` and defaults it to `ON` for Apple builds. The Apple source selection then chooses desktop Cocoa files such as macOS main, video, console, and system implementations.

Required bounded change:

- add a dedicated iOS platform source set;
- do not compile the macOS Cocoa entry point or desktop windowing implementation for iPhone;
- evaluate reuse of portable POSIX code separately from UIKit/SDL lifecycle code.

Simply setting `OSX_COCOA_BACKEND=OFF` is not sufficient proof because the fallback source set is SDL desktop-oriented and includes crash handling and window assumptions that still require review.

### 3.3 Desktop Apple frameworks are linked

The OpenAL path adds Apple frameworks including `ApplicationServices`. That framework selection is desktop-oriented.

Required bounded change:

- use static OpenAL Soft for the initial target;
- link only iOS-available audio frameworks required by the selected OpenAL Soft configuration;
- prohibit runtime loading of an arbitrary OpenAL dynamic library.

### 3.4 No dedicated iOS platform directory was found

The source audit currently finds no dedicated iOS or iPhone platform layer. Therefore, successful macOS support must not be misrepresented as iOS support.

## 4. Initial configuration decisions

The first arm64 compile experiment should use these policy decisions:

- `HAVE_VM_JIT=OFF`
- `FORCE_INTERNAL_BZIP2=ON`
- `DYN_OPENAL=OFF`
- `SEND_ANON_STATS=OFF`
- disable or omit Discord RPC
- no GTK
- no Steam integration
- no signing or IPA packaging
- no proprietary Selaco data
- controller and touch implementation out of scope

`HAVE_VULKAN=ON` remains the intended renderer direction, but the first experiment may compile platform-independent engine libraries before the MoltenVK surface layer exists.

## 5. Open questions requiring evidence

1. Which exact ZMusic revision and codec dependencies are expected by the pinned engine?
2. Can libvpx be compiled cleanly for arm64 iOS with the required feature set?
3. Which Vulkan extensions and formats does GZSelaco require beyond MoltenVK's exposed set?
4. Does the BC1/BC3/BC7 compressed texture path work unchanged through MoltenVK on A18 Pro?
5. Which POSIX platform files are reusable without desktop APIs?
6. Does the interpreted VM sustain acceptable frame time in a representative combat scene?
7. Can the verified native host executables be imported cleanly into the target CMake build?
8. Are any bundled third-party licences incompatible with the intended private or eventual public distribution model?

## 6. Next bounded experiment

Create a macOS-hosted, arm64-iOS CMake configure probe that:

1. fetches the exact pinned source;
2. consumes the separately built native host tools;
3. configures the target build with the initial policy decisions above;
4. stops after configuration or the first classified compile boundary;
5. archives the exact CMake cache, command line, and first failure log;
6. does not patch around multiple unrelated failures in one run.

Passing this experiment authorizes only the next compile boundary. It does not authorize an app shell, renderer launch, game-data import, packaging, signing, or gameplay work.
