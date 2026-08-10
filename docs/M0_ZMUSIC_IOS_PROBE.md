# Milestone 0 ZMusic iOS Probe

Last updated: 2026-07-19

## Purpose

Determine whether a complete static ZMusic library exposing the APIs used by the pinned GZSelaco engine can be built for physical-device arm64 iPhoneOS.

GZSelaco does not encode an exact ZMusic revision. This experiment therefore uses an explicit compatibility-trial pin rather than claiming an upstream-designated canonical version.

## Trial input

- Repository: `https://github.com/ZDoom/ZMusic.git`
- Commit: `d3b730795784bff3f97571446101c57c1c6ac9bc`
- Declared project version: `1.3.0`
- Target: arm64 iPhoneOS
- Deployment target: iOS 15.0
- Linkage: static

The pin is recorded in `DEPENDENCY_TRIAL_PINS.env`.

## Bounded iOS adaptations

The probe applies reproducible source edits through `scripts/patch-zmusic-ios-m0.py`:

1. Prevent the macOS `10.9` deployment target from overriding an iOS toolchain.
2. Make bundled FluidSynth optional.
3. Disable FluidSynth for the initial iOS target and compile a null factory from `overlays/zmusic-ios/music_fluidsynth_stub.cpp`.
4. Exclude the macOS hardware CoreMIDI backend from iOS.
5. Keep software MIDI backends and the public ZMusic API available.
6. Disable dynamic libsndfile and mpg123 loading.

### Why FluidSynth is disabled

The bundled FluidSynth configuration requires GLib for non-Windows platforms. During the first iOS build it attempted to consume the host macOS Homebrew GLib package, which is not an iPhoneOS dependency and cannot be linked into an arm64 device library.

Porting FluidSynth's GLib dependency or replacing its platform abstraction is a separate task. It is not required to prove that ZMusic itself and its other software synthesizer backends can compile for iOS.

### Why system CoreMIDI is disabled

ZMusic's Apple hardware-MIDI backend is explicitly written for macOS and includes `CoreAudio/HostTime.h`, which is absent from the iPhoneOS SDK. System hardware MIDI output is not required for Selaco's first mobile target.

Disabling this backend does not disable software-synthesized music playback.

## API contract

`probes/zmusic-api-contract.cpp` compiles against the built headers and exercises the declarations GZSelaco uses, including:

- callback registration;
- GENMIDI, OPN, and GUS data registration;
- MIDI type identification;
- MIDI source creation;
- in-memory song opening;
- volume-change notification;
- statistics access;
- stream closure.

The produced static library is also inspected for the corresponding exported symbols.

## Verified result

- Workflow: `Milestone 0 ZMusic iOS Probe`
- Run: `29687858702`
- Head: `d2c8a47f1a0f2daae85794a9660d502acc960a40`
- Job: `88195248688`
- Conclusion: success

Artifacts:

- Static library and API-contract artifact: `8442657394`
- Artifact digest: `sha256:645987ebd7d4a0d35c62c90a433ef177bee6a603ea8a71f779f4b887c6de0998`
- Evidence artifact: `8442657216`
- Evidence digest: `sha256:0bc361ebe1d48acf157714c48d7224ed3c2a5bd8dd1a0ff5b2ae3f53c8166d0c`

The successful artifact contains:

- `libzmusic-ios-arm64.a`;
- `zmusic-api-contract.o`;
- a reproducible archive of the probe output.

## Classification

- **Static ZMusic arm64 iPhoneOS build:** VERIFIED
- **GZSelaco-facing API declarations:** VERIFIED by compile contract
- **GZSelaco-facing library symbols:** VERIFIED
- **FluidSynth backend:** intentionally disabled, NOT PORTED
- **macOS hardware CoreMIDI backend:** intentionally excluded from iOS
- **Software MIDI backends:** compiled, NOT PHYSICALLY EXECUTED
- **Music playback in GZSelaco:** NOT YET VERIFIED
- **Audio output integration:** NOT YET VERIFIED
