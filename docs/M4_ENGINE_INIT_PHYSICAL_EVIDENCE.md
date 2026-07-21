# Milestone 4A Physical Engine Initialization Evidence

## Result

**PASS on the target iPhone.**

The physically installed Milestone 4A IPA reached the deliberately bounded pre-renderer engine initialization boundary while the diagnostic Vulkan presenter remained alive.

Observed terminal status:

```text
phase=m4_engine_init_boundary_reached GameMain returned bounded probe code 75
```

This confirms that the real pinned GZSelaco startup advanced beyond the Milestone 3 IWAD-recognition boundary and completed the authorized M4A initialization path through resource mounting, configuration, DEFCVARS processing, and palette setup before stopping immediately ahead of `V_Init2()`.

## Physical display evidence

The user-provided screenshot visibly reports:

- UIKit lifecycle: PASS
- Metal layer: PASS
- Vulkan device: Apple A18 Pro GPU
- Swapchain: PASS
- Format: BGRA8 UNORM
- Extent: 2868 x 1320
- Images: 3
- Present mode: FIFO
- Graphics/present queue: 0
- Frames presented: 510
- Last VkResult: 0
- Terminal engine phase: `m4_engine_init_boundary_reached`
- Bounded `GameMain()` return code: 75

Screenshot identity:

- Dimensions: 2868 x 1320
- Size: 207,053 bytes
- SHA-256: `7c745ebd3f03c6b726e7f155db1043b4f5c2c7c08539aa5169627b8588e71091`

A second user-provided screenshot shows the surviving iOS Files containers for `SelacoiOS Engine Init` and the historical `SelacoiOS Local Asset` app.

Files screenshot identity:

- Dimensions: 1320 x 2868
- Size: 832,431 bytes
- SHA-256: `388a7f702bb4df3aa6e80fe91c9989366b8337a330431d1efc1a695dd6aefb61`

## Proven engine boundary

The physical pass supports these claims:

1. The local user-supplied licensed `Selaco.ipk3` remained discoverable and readable through the app's Documents container.
2. Its ZIP/IPK3 signature and local SHA-256 validation completed.
3. The real pinned `GameMain()` entered.
4. Public `gzdoom.pk3` loading completed.
5. `FIWadManager` recognized the local Selaco IWAD.
6. `PClass::StaticInit()` and `PType::StaticInit()` completed.
7. `D_InitGame()` entered.
8. Dummy screen-size and framebuffer setup completed.
9. Game metadata and `GameConfig::DoGameSetup()` completed.
10. The selected archives were mounted through `FileSystem::InitMultipleFiles()`.
11. DEFCVARS processing completed.
12. Palette initialization completed.
13. Execution stopped before `V_Init2()` and before GZSelaco created an independent Vulkan renderer.
14. The diagnostic Vulkan presenter remained healthy for at least 510 frames with final `VkResult` 0.

## Stable development app identity

Starting with this physical pass, `SelacoiOS Engine Init` is the sole active development test app.

Future renderer, title, and menu candidates must reuse:

- Bundle identifier: `am.arjunkl.selacoios.engineinit.m4`
- Files container display name: `SelacoiOS Engine Init`
- Licensed asset location: `Documents/Selaco/Selaco.ipk3`

Do not allocate a new bundle identifier or Files container for each incremental probe unless an iOS platform constraint demonstrates that a separate identity is required.

The Milestone 3 `SelacoiOS Local Asset` app and its bundle identity remain historical controls in Git and Actions evidence, but the installed app may be removed from the test device.

## Next authorized boundary

The next experiment may be more aggressive while remaining controlled:

1. pause and invalidate the diagnostic `CADisplayLink`;
2. wait for the diagnostic Vulkan device to become idle;
3. destroy the diagnostic swapchain, device, surface, instance, and Volk dispatch state;
4. retain UIKit and the existing `CAMetalLayer`;
5. initialize the real GZSelaco Vulkan loader and Metal surface path;
6. allow `V_Init2()` and renderer/framebuffer creation;
7. continue toward the first engine-owned submitted/presented frame and title/menu boundary;
8. stop at the first reproducible unexplained failure or after a physically testable title/menu candidate is produced.

The same Engine Init app identity must be reused.

## Remaining non-claims

This result does not yet prove:

- diagnostic-to-engine Vulkan handoff;
- engine Vulkan instance, device, surface, or swapchain creation;
- an engine-owned submitted or presented frame;
- shader compilation on the A18 Pro;
- title or menu rendering;
- audio, input, saves, gameplay, lifecycle restoration, or performance.

A successful M4A pass authorizes the controlled renderer-handoff experiment above. It does not authorize gameplay work beyond the title/menu boundary.
