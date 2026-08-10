# Milestone 1 Physical Vulkan Surface Evidence

## Outcome

**PASS on physical iPhone hardware.**

The Milestone 1 dynamic-MoltenVK runtime build was installed and launched on the target iPhone 16 Pro Max. A user-provided physical-device screenshot showed the following exact runtime results:

- UIKit lifecycle: `PASS`
- Metal layer: `PASS`
- Vulkan + Metal surface: `PASS`
- Physical device: `Apple A18 Pro GPU`
- Graphics/present queue: `0`
- VkResult: `0`
- Detail: `instance, physical device, graphics/present queue, and Metal surface passed`

The probe deliberately reported:

- no `Selaco.ipk3` loaded;
- no swapchain created;
- no GZSelaco game loop started.

## Physical evidence identity

The screenshot supplied after installing the Milestone 1 IPA had:

- SHA-256: `fb3eac4410c5c95bdd983c337fd77d6bb9eeb89ed65661ac3173432cf52b255d`
- Size: `163,893` bytes

The image itself is not committed to the repository. The hash identifies the exact evidence received during the physical test.

## Build under test

- Workflow: `Milestone 1 Runtime Bootstrap App`
- Run: `29702317741`
- Tested branch head: `dee8d9a44f7f23cbe9490c8e21f62ff9d2806d8d`
- Bundle version: `0.3.0 (3)`
- Bundle identifier: `am.arjunkl.selacoios.runtime.m1`
- IPA artifact ID: `8446874575`
- Inner IPA SHA-256: `d0f644b507b56ed52bab9e993efcdca8c13ba1d29d9b49b8e1f6b91a0aaa2cd1`

## Verified boundary

This result verifies the physical-device path through:

1. UIKit application lifecycle;
2. `CAMetalLayer` creation;
3. embedded dynamic `MoltenVK.framework` loading;
4. Volk dispatch initialization from MoltenVK's exported `vkGetInstanceProcAddr`;
5. Vulkan instance creation;
6. `VkMetalSurfaceEXT` creation;
7. Apple A18 Pro physical-device enumeration;
8. discovery of a graphics and presentation-capable queue family.

## Explicit non-claims

This evidence does not verify:

- logical-device creation;
- swapchain creation;
- image acquisition, queue submission, or presentation;
- GZSelaco renderer integration;
- commercial game-data loading;
- menu startup, controls, audio, video, saves, gameplay, or performance.
