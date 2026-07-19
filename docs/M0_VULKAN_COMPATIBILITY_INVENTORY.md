# Milestone 0 Vulkan Compatibility Inventory

Last updated: 2026-07-19

## Scope

This inventory compares the pinned GZSelaco engine revision in `SOURCE_PIN.env` with the pinned MoltenVK iOS package in `MOLTENVK_PIN.env`.

It distinguishes source-level compatibility from physical-device runtime proof. A symbol appearing in a linked arm64 iPhoneOS executable does not prove that the corresponding feature works correctly on an A18 Pro.

## Pinned inputs

- GZSelaco: `TheCockatrice/GZSelaco` at `7543afd533ea7c60ed61d2b6ad7518656d77097b`
- MoltenVK: `KhronosGroup/MoltenVK` release `v1.4.1`
- MoltenVK iOS asset: `MoltenVK-ios.tar`
- MoltenVK asset SHA-256: `54336b90212c390ed5935c96460aed3bf651ad7d3c0f0e956586ce18e9c0b701`
- Initial runtime target: iPhone 16 Pro Max / A18 Pro / arm64

## Verified engine requirements

### Instance API levels

GZSelaco's `VulkanInstanceBuilder` tries Vulkan API versions in this order:

1. Vulkan 1.2
2. Vulkan 1.1
3. Vulkan 1.0

The Milestone 0 shell currently requests Vulkan 1.1 for its bounded instance and surface self-tests. This is intentionally narrower than starting the full renderer.

### Instance extensions

GZSelaco treats these as optional during ordinary instance construction:

- `VK_KHR_get_surface_capabilities2`
- `VK_KHR_get_physical_device_properties2`

When a presentation surface is required, GZSelaco requires:

- `VK_KHR_surface`
- one platform-specific surface extension

The pinned engine currently has platform branches for Win32, obsolete macOS MVK, and Xlib. It has no iOS or `VK_EXT_metal_surface` branch.

### Required device extension for presentation

When a surface is supplied, GZSelaco requires:

- `VK_KHR_swapchain`

### Optional device extensions

The engine opportunistically enables:

- `VK_KHR_dedicated_allocation`
- `VK_KHR_get_memory_requirements2`
- `VK_EXT_descriptor_indexing`
- `VK_EXT_swapchain_colorspace`

The optional ray-query path requests:

- `VK_KHR_buffer_device_address`
- `VK_KHR_acceleration_structure`
- `VK_KHR_deferred_host_operations`
- `VK_KHR_ray_query`

The ray-query path is optional and must remain disabled when the complete extension set is unavailable.

### Required physical-device features

A device is rejected unless all of these core feature bits are true:

- `samplerAnisotropy`
- `fragmentStoresAndAtomics`
- `multiDrawIndirect`
- `independentBlend`

The engine also conditionally enables these when present:

- `depthClamp`
- `shaderClipDistance`
- buffer device address
- acceleration structures
- ray queries
- descriptor-indexing feature bits

### Queue assumptions

The renderer requires a graphics-capable queue family. Its upload-queue selection also assumes one of the following can be found:

- a second graphics queue with image-transfer granularity of 1;
- a transfer-capable queue meeting the same granularity condition; or
- a compute-capable fallback meeting the same condition.

When presenting, at least one queue family must support the Vulkan surface.

These conditions require physical-device enumeration and cannot be proved by the linker.

## MoltenVK v1.4.1 source-level coverage

MoltenVK v1.4.1 documents support for the mandatory and ordinary optional extensions needed by the current renderer path:

| Requirement | Status | Notes |
|---|---|---|
| Vulkan 1.0-1.2 API range | Supported at source level | MoltenVK v1.4.1 implements a Vulkan 1.4 portability subset. |
| `VK_KHR_surface` | Documented supported | Required for presentation. |
| `VK_EXT_metal_surface` | Documented supported | Required iOS surface path. |
| `VK_KHR_swapchain` | Documented supported | Runtime swapchain behaviour remains unverified. |
| `VK_KHR_get_surface_capabilities2` | Documented supported | Optional in GZSelaco. |
| `VK_KHR_get_physical_device_properties2` | Documented supported | Optional in GZSelaco. |
| `VK_KHR_dedicated_allocation` | Documented supported | Optional in GZSelaco. |
| `VK_KHR_get_memory_requirements2` | Documented supported | Optional in GZSelaco. |
| `VK_EXT_descriptor_indexing` | Documented supported with limits | Device feature bits and practical descriptor limits must be queried on A18 Pro. |
| `VK_EXT_swapchain_colorspace` | Documented supported | HDR is not part of the first target. |
| `VK_KHR_buffer_device_address` | Documented supported conditionally | Requires suitable Metal argument-buffer support. |
| `VK_KHR_deferred_host_operations` | Documented supported | Part of the optional ray-query group. |
| `VK_KHR_acceleration_structure` | Not listed as supported | Optional ray-query path must not be assumed. |
| `VK_KHR_ray_query` | Not listed as supported | Optional ray-query path must not be assumed. |

MoltenVK specifically requires visible Apple-platform presentation to use `VK_EXT_metal_surface` with a `CAMetalLayer` and the `VK_USE_PLATFORM_METAL_EXT` compile guard.

## Implemented Milestone 0 boundary

The iOS shell now:

- links the exact pinned `ios-arm64/libMoltenVK.a`;
- includes the pinned package's Vulkan headers;
- compiles a Vulkan instance create/destroy self-test;
- compiles a `CAMetalLayer` surface create/destroy self-test using `VK_EXT_metal_surface`;
- links `vkCreateInstance`, `vkDestroyInstance`, `vkCreateMetalSurfaceEXT`, and `vkDestroySurfaceKHR` into an unsigned physical-device Mach-O;
- preserves the unsigned `.app` and build evidence as separate GitHub Actions artifacts.

Verified workflow:

- Workflow: `Milestone 0 iOS Shell Link Probe`
- Run: `29686759027`
- Head: `2e957157133645bcff46217c71a391fe632bb369`
- Evidence artifact: `8442304289`
- Evidence artifact digest: `sha256:eec660db75f814852d64a06238271f8324da21294342026e9e4a921944ee5ae8`
- Unsigned app artifact: `8442304390`
- Unsigned app artifact digest: `sha256:46c65677973b9d1f5edd6ab8b3073472edc506106b80548d67bc84ca5676a41a`

## Required integration change

The full GZSelaco platform layer must gain an iOS surface path that:

1. defines `VK_USE_PLATFORM_METAL_EXT` before including Vulkan platform headers;
2. requests `VK_KHR_surface` and `VK_EXT_metal_surface`;
3. obtains the `CAMetalLayer` owned by the iOS view;
4. creates the surface with `vkCreateMetalSurfaceEXT`;
5. keeps the view/layer lifecycle synchronized with suspension, resize, and restoration;
6. never selects the obsolete macOS-only `VK_MVK_macos_surface` path.

The Milestone 0 shell proves that this path compiles and links. It does not yet modify the full engine's surface abstraction.

## Remaining runtime unknowns

The following remain unverified until a physical-device executable is authorized, signed, installed, and its logs are captured:

- Vulkan instance creation result on the A18 Pro;
- `CAMetalLayer` surface creation result;
- required core device feature bits;
- graphics, upload, and present queue topology;
- `minImageTransferGranularity` assumptions;
- BC1, BC3, and BC7 format exposure and upload behaviour;
- swapchain format and present-mode selection;
- shader translation and SPIR-V compatibility;
- descriptor indexing limits;
- memory-budget behaviour;
- suspend/resume and surface-loss recovery;
- sustained thermal performance.

## Current classification

- **Instance link boundary:** VERIFIED
- **Metal-surface link boundary:** VERIFIED
- **Physical Vulkan instance:** NOT YET VERIFIED
- **Physical Metal surface:** NOT YET VERIFIED
- **Swapchain:** NOT STARTED
- **Full GZSelaco renderer:** NOT STARTED
- **Selaco content rendering:** NOT STARTED
