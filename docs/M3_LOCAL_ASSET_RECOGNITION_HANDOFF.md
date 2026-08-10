# Milestone 3 Local Asset Recognition Handoff

## Scope

Milestone 3 privately tests a user-owned `Selaco.ipk3` on physical iOS hardware without committing, uploading, bundling, or redistributing that file.

The app retains the physically proven Milestone 2 Vulkan clear-frame presenter while a bounded background probe:

1. looks for `Documents/Selaco/Selaco.ipk3`;
2. verifies readability, non-zero size, and a ZIP/IPK3 signature;
3. computes a local SHA-256 identity;
4. starts the real pinned GZSelaco `GameMain()` with `-iwad <local path>`;
5. lets `FIWadManager::FindIWAD` classify the archive;
6. stops before `D_InitGame`, renderer takeover, scripting, audio, or the game loop.

No licensed data participates in GitHub Actions.

## CI identity

- Workflow: `Milestone 3 Local Asset Recognition`
- Run: `29719544432`
- CI-tested head: `9be58028e032bcf19f60a08bf43d2193bd4fccda`
- Outcome: PASS

## Unsigned IPA artifact

- Artifact name: `selaco-m3-local-asset-recognition-unsigned-ipa`
- Artifact ID: `8451969062`
- GitHub artifact digest: `sha256:07ae1bc9cf5c09759c56ac83b84d6b158d5a83f766e5dc6a3bc22985a1a3d15a`
- GitHub artifact size: `11,140,749` bytes
- Expires: 2026-08-03

Contained IPA:

- File: `Selaco-local-asset-probe-unsigned.ipa`
- SHA-256: `53873fbba45732957dfd340773cf3ccb35c3c7f753005717cc0c6a4781efad13`
- Size: `11,158,134` bytes
- Bundle identifier: `am.arjunkl.selacoios.localasset.m3`
- Version/build: `0.5.0 (5)`

## Public support archive

The IPA contains `gzdoom.pk3`, generated from the pinned public GZSelaco source during CI.

- SHA-256: `4042aa000c25fb1ce2ff9d85a93cb892fb4facf9d43dbc15757efb5ac2e042c9`
- Size: `2,661,130` bytes

The IPA does not contain `Selaco.ipk3`, provisioning profiles, `.p12` files, or private signing material.

## Physical test procedure

1. Sign and install the exact IPA.
2. Launch it once. The blue Vulkan presenter should remain active and the local-asset status should report that the asset is missing.
3. In Files, open `On My iPhone > SelacoiOS Local Asset > Selaco`.
4. Copy the user's licensed file into that directory as `Selaco.ipk3`.
5. Force-quit and relaunch the app.
6. Keep the app open while it validates the file and runs the bounded engine probe.

Expected success status:

```text
phase=m3_engine_iwad_recognized GameMain returned bounded probe code 73
```

Expected persistent files:

- `Documents/Selaco/runtime-bootstrap.txt`
- `Documents/Selaco/swapchain-status.txt`
- `Documents/Selaco/licensed-asset-status.txt`

## Stop boundary

A successful recognition result proves only that the real pinned GZSelaco IWAD manager accepts the local licensed archive.

It does not prove or authorize:

- `D_InitGame` completion;
- engine renderer integration;
- scripting or gameplay initialization;
- menu rendering;
- audio or video playback;
- controls or saves;
- licensed-data redistribution;
- merge or release readiness.
