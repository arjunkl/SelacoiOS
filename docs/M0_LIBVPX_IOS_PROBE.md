# Milestone 0 libvpx iOS Probe

Last updated: 2026-07-19

## Purpose

Verify that the libvpx revision implied by GZSelaco's pinned vcpkg baseline can be built as a decoder-only static library for physical-device arm64 iPhoneOS, and that the public decoder APIs used by GZSelaco link into an iOS Mach-O.

## Pinned input

GZSelaco's vcpkg baseline resolves libvpx to version `1.12.0`, port-version `2`.

The corresponding exact upstream input used by this probe is:

- Repository: `https://github.com/webmproject/libvpx.git`
- Commit: `03265cd42b3783532de72f2ded5436652e6f5ce3`
- Upstream version: `1.12.0`
- Target: arm64 iPhoneOS
- Deployment target: iOS 15.0
- Linkage: static

The pin is recorded in `DEPENDENCY_TRIAL_PINS.env`.

## Build policy

The first mobile target builds only what the game requires:

- VP8 decoder: enabled
- VP9 decoder: enabled
- VP8 encoder: disabled
- VP9 encoder: disabled
- tools, examples, documentation, and unit tests: disabled
- shared library: disabled
- runtime CPU detection: disabled
- position-independent code: enabled

The iPhoneOS SDK and minimum deployment target are supplied through AppleClang compile and linker flags. libvpx 1.12.0 predates later convenience options such as `--sdk-path` and `--extra-ldflags`, so the probe deliberately uses the version's supported configuration interface rather than pretending old software reads new documentation.

## GZSelaco usage inventory

The pinned GZSelaco source directly consumes libvpx in:

- `src/common/cutscenes/movieplayer.cpp`
- `src/common/textures/animtexture.cpp`

The relevant path is decoder-only. It uses VP8/VP9 decoder interfaces, codec initialization, packet decoding, frame retrieval, error reporting, image access, and codec destruction. No encoder path is required by the game runtime.

## Link contract

`probes/libvpx-decoder-contract.cpp` links an arm64 iPhoneOS executable against the produced static library and verifies the availability of:

- `vpx_codec_vp8_dx`
- `vpx_codec_vp9_dx`
- `vpx_codec_dec_init_ver`
- `vpx_codec_decode`
- `vpx_codec_get_frame`
- `vpx_codec_destroy`
- `vpx_codec_version_str`

The probe also rejects libraries that unexpectedly retain VP8 or VP9 encoder interfaces.

The contract is linked but not executed because GitHub's macOS runner cannot execute a physical-device iPhoneOS binary.

## Verified result

- Workflow: `Milestone 0 libvpx iOS Probe`
- Run: `29688440311`
- Head: `79ffae8fe02d59e19cd566a56f971672178c2bea`
- Job: `88196781905`
- Conclusion: success

Artifacts:

- Decoder library, headers, and contract: `8442811842`
- Artifact digest: `sha256:dc2f735cb91dae44f0a468ad749f30372f1a638e0da032d5b6f487b969d801d9`
- Evidence artifact: `8442811755`
- Evidence digest: `sha256:9fdc01e4a85ebdd85e74579b3b95bda9ef4ff64c2e519eb61426831112e612a6`

## Classification

- **Static libvpx arm64 iPhoneOS build:** VERIFIED
- **VP8 decoder symbols:** VERIFIED
- **VP9 decoder symbols:** VERIFIED
- **Encoder exclusion:** VERIFIED
- **iPhoneOS decoder contract link:** VERIFIED
- **Decoder contract execution:** NOT APPLICABLE IN CI
- **GZSelaco movie playback:** NOT YET VERIFIED
- **Animated VPX texture playback:** NOT YET VERIFIED
- **Physical-device decoding and performance:** NOT YET VERIFIED
