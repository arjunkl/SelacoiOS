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
- The exact Milestone 0 source revision is recorded in `SOURCE_PIN.env`.
- The pinned source declares C++17, a cross-compilation switch, Vulkan support, an x86_64-only default VM JIT gate, a GZDoom 4.13 engine baseline, and the `SELACO` game signature.

### REPORTED BUT NOT YET VERIFIED IN THIS REPOSITORY

- GZSelaco can compile for arm64 iOS.
- MoltenVK exposes every Vulkan feature Selaco requires.
- BC-compressed Selaco textures upload and render correctly on the A18 Pro through MoltenVK.
- Interpreted ZScript performance is sufficient for combat-heavy gameplay.
- Audio, video playback, save/load, and controller handling can be integrated without replacing major engine subsystems.

### UNKNOWN

- Exact dependency closure and licence obligations for an iOS binary.
- Required MoltenVK extensions and feature fallbacks.
- Sustained thermal and memory behaviour.
- Minimum practical iPhone generation.
- Whether existing non-public GZDoom iOS work can be reused lawfully and technically.

## 3. Source identity

Authoritative source pin:

- Repository: `https://github.com/TheCockatrice/GZSelaco.git`
- Commit: `7543afd533ea7c60ed61d2b6ad7518656d77097b`
- Upstream branch at selection: `master`

The commit hash, not the moving branch name, controls Milestone 0. Updating it requires a fresh source and compatibility audit.

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
2. Pin GZSelaco to an exact upstream revision.
3. Build native host tools for macOS where cross-compilation requires executable generators.
4. Cross-compile engine libraries for arm64 iOS with JIT disabled.
5. Integrate SDL/iOS lifecycle and MoltenVK only after the static engine boundary is understood.
6. Reach a controller-only menu and first-map proof before implementing touch controls.
7. Import proprietary game data at runtime from outside the repository.

The final source-integration mechanism, such as a maintained fork, submodule, or subtree, is intentionally undecided until the dependency and licence audit is complete.

## 6. Milestone gates

### Milestone 0A: static source and dependency audit

Required evidence:

- exact source pin resolves reproducibly;
- dependency inventory with licence and iOS status;
- host-tool inventory;
- platform-specific source inventory;
- Vulkan feature and extension inventory;
- no proprietary data required.

### Milestone 0B: arm64 compile boundary

Required evidence:

- macOS host tools build successfully;
- GZSelaco translation units compile for arm64 iOS;
- x86-only JIT and assembly are excluded cleanly;
- failures are classified by subsystem rather than patched blindly.

### Milestone 0C: engine link boundary

Required evidence:

- engine and dependencies link into an unsigned physical-device target;
- no unresolved desktop-only symbols remain unexplained;
- the binary uses only permitted iOS APIs;
- no claim of launch or rendering is made yet.

### Milestone 1: first physical-device presentation

Required evidence:

- application launches on the target iPhone;
- MoltenVK surface and swapchain initialize;
- engine reaches the real Selaco menu using user-supplied data;
- controller navigation works;
- logs are preserved.

### Milestone 2: first playable level

Required evidence:

- first gameplay area loads;
- textures, audio, video, scripting, saves, and controller actions are validated;
- repeatable performance measurements are recorded.

Touch, gyro, broad device support, packaging polish, and public distribution are later work and are not authorized by an earlier gate passing.

## 7. Stop conditions

Stop and document rather than broaden the work if any of the following occurs:

- a required dependency cannot legally or technically ship on iOS;
- proprietary Selaco data is required in CI or Git history;
- the engine requires prohibited runtime code generation to function correctly;
- MoltenVK lacks a required feature and no bounded fallback exists;
- a build failure cannot be reduced to a specific subsystem or reproducible command;
- success would require rewriting shared history or discarding unrelated work;
- a later milestone is reached accidentally without the evidence required for its gate.

## 8. Current work order

The active work order is limited to Milestone 0 bootstrap:

1. protect the proprietary asset boundary;
2. pin and audit the exact GZSelaco source revision;
3. establish CI static gates;
4. inventory dependencies, host tools, and iOS-incompatible platform code;
5. prepare a bounded macOS/arm64 compile experiment.

No source import, gameplay implementation, touch controls, IPA packaging, signing, or public distribution is authorized by this bootstrap alone.
