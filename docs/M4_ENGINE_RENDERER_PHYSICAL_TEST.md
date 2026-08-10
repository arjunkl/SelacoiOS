# Milestone 4B Engine Renderer and Title/Menu Physical Test

## Scope

This candidate reuses the physically proven **SelacoiOS Engine Init** app and its existing Files container. It performs a controlled Vulkan ownership handoff:

1. UIKit creates and retains the existing `CAMetalLayer`.
2. The diagnostic presenter proves the known Vulkan clear-frame path.
3. `CADisplayLink` is invalidated.
4. The diagnostic queue/device is idled.
5. Its swapchain, device, Metal surface, instance, Volk dispatch state, and dynamic MoltenVK handle are destroyed.
6. The real pinned GZSelaco Vulkan backend starts from a clean loader state.
7. GZSelaco creates its own Vulkan instance, `VkMetalSurfaceEXT`, device, swapchain, framebuffer, and renderer state on the existing layer.
8. Startup continues toward menus, the title loop, and the first engine-owned presented frame.

The candidate does not create another app identity.

## Stable app identity

- Bundle identifier: `am.arjunkl.selacoios.engineinit.m4`
- Display name: `SelacoiOS Engine Init`
- Licensed asset location: `Files > On My iPhone > SelacoiOS Engine Init > Selaco > Selaco.ipk3`
- Version/build for this candidate: `0.7.0 (7)`

Install this IPA as an update to the existing Engine Init app. Do not delete the Engine Init app or its Files folder before testing, because doing so also deletes the locally supplied `Selaco.ipk3`.

The historical `SelacoiOS Local Asset` app may be removed from the device.

## Expected progression

The on-screen diagnostic text should show the known clear-frame presenter first. It should then change to:

```text
Diagnostic Vulkan: released
Starting GZSelaco renderer…
```

The status overlay is hidden only after the first successful engine-owned Vulkan presentation. At that point, the expected visible result is the earliest GZSelaco/Selaco title or menu frame.

Useful persistent phases include:

- `phase=m4_renderer_handoff_requested`
- `phase=m4_renderer_handoff_passed`
- `phase=m4_engine_moltenvk_loader_passed`
- `phase=m4_engine_volk_dispatch_ready`
- `phase=m4_engine_vulkan_instance_create_passed`
- `phase=m4_engine_metal_surface_create_passed`
- `phase=m4_engine_render_device_construct_passed`
- `phase=m4_v_init2_passed`
- `phase=m4_menu_init_passed`
- `phase=m4_title_loop_started`
- `phase=m4_engine_loop_entered`
- `phase=m4_engine_first_frame_presented`

## Evidence files

Under `Files > On My iPhone > SelacoiOS Engine Init > Selaco`:

- `runtime-bootstrap.txt`
- `engine-init-status.txt`
- `licensed-asset-status.txt`
- `renderer-init-status.txt`
- `swapchain-status.txt`

If the app remains on a status screen or exits, preserve the final lines of `runtime-bootstrap.txt`, the complete `renderer-init-status.txt`, and the newest Selaco Analytics report from:

`Settings > Privacy & Security > Analytics & Improvements > Analytics Data`

Do not upload or attach `Selaco.ipk3`.

## Success boundary

A physically testable success requires at least one of:

- a visible title/menu frame;
- persistent `phase=m4_engine_first_frame_presented` followed by title-loop evidence;
- a reproducible later failure after the first engine-owned frame, with preserved logs.

Stop at the first reproducible unexplained failure. A title/menu frame does not authorize gameplay work.
