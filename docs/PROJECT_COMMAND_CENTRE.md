# SELACOIOS PROJECT COMMAND CENTRE

Last updated: 2026-07-19

## 1. Intended outcome

Produce an engine-only native iOS application capable of running Selaco with game data imported by the user from a legally obtained installation.

Initial validation target:

- iPhone 16 Pro Max
- A18 Pro / arm64
- physical device, not simulator-only proof
- landscape presentation
- external controller input first
- Vulkan renderer through MoltenVK, subject to evidence
- user-imported `Selaco.ipk3`

No public App Store, TestFlight, commercial, or redistributable release is currently authorized or implied.

## 2. Evidence status

### VERIFIED

- Repository `arjunkl/SelacoiOS` exists and is writable.
- The project repository contains no commercial Selaco game data at bootstrap.
- GZSelaco source is publicly accessible at `TheCockatrice/GZSelaco`.
- The exact Milestone 0 GZSelaco source revision is recorded in `SOURCE_PIN.env`.
- The pinned source declares C++17, a cross-compilation switch, Vulkan support, an x86_64-only default VM JIT gate, a GZDoom 4.13 engine baseline, and the `SELACO` game signature.
- Native macOS host tools `re2c`, `lemon`, and `zipdir` build from the pinned source.
- The host-tools probe also compiles the pinned bundled BZip2, LZMA, and miniz targets required by `zipdir`.
- A bounded GZSelaco core slice compiles for physical-device arm64 iPhoneOS with the x86 JIT path excluded.
- MoltenVK release `v1.4.1` is pinned through `MOLTENVK_PIN.env`.
- The official `MoltenVK-ios.tar` release asset resolves and matches SHA-256 `54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701`.
- The pinned MoltenVK package contains a physical-device `ios-arm64/libMoltenVK.a` and Vulkan headers.
- An unsigned arm64 iPhoneOS `.app` links against UIKit, CoreGraphics, IOSurface, Foundation, QuartzCore, Metal, MetalKit, the pinned GZSelaco boundary, and the pinned MoltenVK static library.
- The linked Mach-O contains bounded self-test paths for Vulkan instance creation/destruction and `CAMetalLayer` surface creation/destruction through `VK_EXT_metal_surface`.
- GZSelaco's current platform surface builder has no iOS `VK_EXT_metal_surface` branch; the missing integration point is classified and reproduced in `docs/M0_VULKAN_COMPATIBILITY_INVENTORY.md`.
- All five Milestone 0 workflows passed together at branch head `2e957157133645bcff46217c71a391fe632bb369`:
  - Static gates: run `29686759012`
  - Host tools: run `29686759014`
  - arm64 iPhoneOS core compile: run `29686759044`
  - MoltenVK package: run `29686759010`
  - iOS shell link: run `29686759027`
- The successful iOS shell run preserved:
  - evidence artifact `8442304289`, digest `sha256:eec660db75f814852d64a06238271f8324da21294342026e9e4a921944ee5ae8`;
  - unsigned `.app` artifact `8442304390`, digest `sha256:46c65677973b9d1f5edd6ab8b3073472edc506106b80548d67bc84ca5676a41a`.

### REPORTED OR COMPILED BUT NOT PHYSICALLY VERIFIED

- The bounded Vulkan instance self-test succeeds on an A18 Pro.
- The bounded `CAMetalLayer` surface self-test succeeds on an A18 Pro.
- MoltenVK exposes every runtime feature, format, and queue property required by the full renderer.
- BC-compressed Selaco textures upload and render correctly on the A18 Pro through MoltenVK.
- Interpreted ZScript performance is sufficient for combat-heavy gameplay.
- Audio, video playback, save/load, and controller handling can be integrated without replacing major engine subsystems.

### UNKNOWN

- Full dependency and licence closure for a complete GZSelaco iOS binary.
- Physical-device Vulkan feature bits, queue topology, and presentation support.
- Swapchain format and present-mode behaviour.
- Sustained thermal and memory behaviour.
- Minimum practical iPhone generation.
- Whether existing non-public GZDoom iOS work can be reused lawfully and technically.

## 3. Source identity

Authoritative GZSelaco source pin:

- Repository: `https://github.com/TheCockatrice/GZSelaco.git`
- Commit: `7543afd533ea7c60ed61d2b6ad7518656d77097b`
- Upstream branch at selection: `master`

Authoritative MoltenVK package pin:

- Repository: `KhronosGroup/MoltenVK`
- Release: `v1.4.1`
- Asset: `MoltenVK-ios.tar`
- SHA-256: `54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701`

Moving branches and mutable release labels do not control Milestone 0. Updating either pin requires a fresh source, package, compatibility, and licence audit.

## 4. Repository boundaries

The repository may contain:

- open-source engine code and compliant modifications;
- iOS platform integration code;
- build scripts and CI configuration;
- documentation, patches, logs, and reproducible metadata;
- original project UI and control assets created for SelacoiOS.

The repository must not contain:

- `Selaco.ipk3` or any renamed copy;
- extracted commercial artwork, maps, audio, video, fonts, or scripts;
- purchased depots or installation archives;
- signed IPA files, provisioning profiles, certificates, or private keys;
- claims of successful execution unsupported by logs or physical-device evidence.

GitHub Actions must never download a purchased Selaco depot or require proprietary game data.

## 5. Architecture direction

The current working direction is:

1. Keep SelacoiOS as the integration, platform, build, and evidence repository.
2. Pin GZSelaco and MoltenVK inputs exactly.
3. Build native host tools for macOS where cross-compilation requires executable generators.
4. Cross-compile engine libraries for arm64 iOS with JIT disabled.
5. Use `VK_EXT_metal_surface` with the `CAMetalLayer` owned by the iOS view.
6. Integrate the verified surface boundary into the full GZSelaco renderer only after dependency closure and a bounded full-engine configure plan exist.
7. Reach a controller-only menu and first-map proof before implementing touch controls.
8. Import proprietary game data at runtime from outside the repository.

The final source-integration mechanism, such as a maintained fork, submodule, or subtree, remains intentionally undecided until dependency and licence closure is complete.

## 6. Milestone gates

### Milestone 0A: static source and dependency audit

Required evidence:

- exact source and binary-package pins resolve reproducibly;
- dependency inventory with licence and iOS status;
- host-tool inventory;
- platform-specific source inventory;
- Vulkan feature and extension inventory;
- no proprietary data required.

Current status: substantially complete. Source identity, host tools, initial dependency inventory, proprietary-data boundary, MoltenVK package identity, and Vulkan compatibility inventory are evidenced. Full third-party licence closure remains open.

### Milestone 0B: arm64 compile boundary

Required evidence:

- macOS host tools build successfully;
- representative GZSelaco translation units compile for arm64 iOS;
- x86-only JIT and assembly are excluded cleanly;
- failures are classified by subsystem rather than patched blindly.

Current status: bounded core slice passed. This does not yet claim that every full-engine translation unit compiles for iOS.

### Milestone 0C: engine link boundary

Required evidence:

- engine-facing code and dependencies link into an unsigned physical-device target;
- no unresolved desktop-only symbols remain unexplained within the bounded target;
- the binary uses permitted iOS frameworks;
- no claim of launch or rendering is made yet.

Current status: bounded platform shell passed with GZSelaco identity code, MoltenVK, Vulkan instance calls, and Metal-surface calls. Full GZSelaco renderer linkage remains open.

### Milestone 1: first physical-device presentation

Required evidence:

- application launches on the target iPhone;
- the bounded Vulkan instance and Metal-surface self-tests pass on device;
- MoltenVK swapchain initializes;
- engine reaches the real Selaco menu using user-supplied data;
- controller navigation works;
- logs are preserved.

Current status: NOT STARTED. The unsigned `.app` artifact is build evidence, not an installable or executed device proof.

### Milestone 2: first playable level

Required evidence:

- first gameplay area loads;
- textures, audio, video, scripting, saves, and controller actions are validated;
- repeatable performance measurements are recorded.

Current status: NOT STARTED.

Touch, gyro, broad device support, packaging polish, and public distribution are later work and are not authorized by an earlier gate passing.

## 7. Stop conditions

Stop and document rather than broaden the work if any of the following occurs:

- a required dependency cannot legally or technically ship on iOS;
- proprietary Selaco data is required in CI or Git history;
- the engine requires prohibited runtime code generation to function correctly;
- MoltenVK lacks a mandatory feature and no bounded fallback exists;
- a build failure cannot be reduced to a specific subsystem or reproducible command;
- success would require rewriting shared history or discarding unrelated work;
- a later milestone is reached accidentally without the evidence required for its gate.

## 8. Current work order

The active work order remains limited to Milestone 0:

1. maintain the proprietary asset boundary;
2. retain exact GZSelaco and MoltenVK pins;
3. preserve successful static, host-tool, arm64 compile, package, and shell-link evidence;
4. complete dependency and licence closure for the components required by a full engine build;
5. convert the classified iOS surface gap into a bounded full-engine integration plan;
6. do not package, sign, install, or claim physical execution under Milestone 0.
