# Milestone 4A Engine Initialization Physical Test

## Scope

Milestone 4A advances the real pinned GZSelaco startup beyond local IWAD
recognition while deliberately stopping immediately before `V_Init2()`.

At that boundary the engine would call `I_InitGraphics()` and create its own
Vulkan renderer/framebuffer. The physically proven diagnostic presenter already
owns Volk global dispatch, a Vulkan instance, device, queue, Metal surface, and
swapchain. Running both ownership systems concurrently has not been proven safe.

Milestone 4A therefore uses renderer strategy C:

- keep UIKit, `CAMetalLayer`, and the diagnostic presenter alive;
- enter the real `GameMain()`;
- initialize core types, configuration, the local licensed IWAD, mounted
  resources, DEFCVARS, and palette state;
- return bounded code `75` immediately before `V_Init2()`;
- preserve the last completed phase in the app Documents directory.

This is an engine-initialization probe, not a title/menu claim.

## Build identity

- Bundle identifier: `am.arjunkl.selacoios.engineinit.m4`
- Version/build: `0.6.0 (6)`
- Expected IPA: `Selaco-engine-init-probe-unsigned.ipa`
- Licensed content in IPA: none
- Audio arguments: `-nosound -nomusic`
- Renderer ownership: diagnostic presenter only
- Engine renderer stop boundary: immediately before `V_Init2()`

## Install and local asset placement

1. Sign and install the exact unsigned IPA using the user's normal private
   sideloading method.
2. Launch once so iOS creates the app's Files container.
3. In Files, open:

   `On My iPhone > SelacoiOS Engine Init > Selaco`

4. Copy the user's licensed file into that directory as:

   `Selaco.ipk3`

5. Force-quit the app.
6. Relaunch and leave it open while the local hash and engine initialization run.

The licensed file must remain user-supplied on-device. Do not upload it to
GitHub, Actions, an issue, a PR, or an evidence archive.

## Expected screen progression

The diagnostic Vulkan clear-frame presenter should remain alive. The status text
should progress through the M4 breadcrumbs and end with a line equivalent to:

```text
phase=m4_engine_init_boundary_reached GameMain returned bounded probe code 75
```

A preceding renderer status should identify:

```text
phase=m4_renderer_creation_deferred M4A stop-before-renderer: diagnostic presenter remains sole Vulkan owner; engine stops immediately before V_Init2
```

## Expected persistent evidence

Under the app's `Selaco` Documents directory:

- `runtime-bootstrap.txt`
- `licensed-asset-status.txt`
- `engine-init-status.txt`
- `renderer-init-status.txt`
- `swapchain-status.txt`

The most useful evidence is:

1. a screenshot showing the final M4 phase and live frame counter;
2. the text of `engine-init-status.txt`;
3. the final section of `runtime-bootstrap.txt`;
4. an iOS Analytics crash report if the process exits.

## Crash report

If the app exits:

1. Open **Settings > Privacy & Security > Analytics & Improvements > Analytics Data**.
2. Find the newest entry beginning with `Selaco`.
3. Share the crash report text without attaching `Selaco.ipk3` or any extracted
   commercial files.

## Success boundary

Milestone 4A passes physically only when the exact installed build reports
bounded code `75` and the diagnostic presenter remains alive.

That proves early real-engine initialization through resource mounting,
configuration, and palette setup. It does not prove:

- engine Vulkan renderer creation;
- an engine-owned submitted or presented frame;
- title/menu rendering;
- input, audio, video playback, saves, gameplay, or performance;
- distribution readiness.
