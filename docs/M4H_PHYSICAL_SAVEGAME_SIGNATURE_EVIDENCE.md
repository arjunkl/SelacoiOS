# Milestone 4H Physical Savegame-Signature Evidence

## Classification

**PHYSICAL PARTIAL PASS on the target iPhone.**

Milestone 4H achieved its bounded compatibility objective: the exact retail Selaco overrides for `GetSavegameFlags` and `GetSavegameTitle` are accepted by the pinned ZScript compiler. Startup progressed beyond the previous missing-virtual and override-signature failures.

The broader title/menu candidate did not complete. Compilation stopped at the next reproducible retail save-menu API boundary.

## Build identity

- Workflow: `Milestone 4H Exact Retail Savegame Signatures and Title Menu`
- Run: `29863542016`
- Branch head: `fd4d1c210318b86004103e3dd76ab28f0d060f97`
- Stable bundle identifier: `am.arjunkl.selacoios.engineinit.m4`
- Display name / Files container: `SelacoiOS Engine Init`
- Version/build: `0.7.8 (15)`
- IPA artifact: `8508681372`
- Contained IPA SHA-256: `869db0008eed9f0bea10006e3e0f89b96418ff07dd35c93331380be8ba3417e1`

The app was installed as an update over the existing Engine Init app, preserving the private `Documents/Selaco/Selaco.ipk3` path.

## Physical evidence identity

The user supplied a physical-device screenshot and the private `zscript-compile.log`. Neither file is committed.

Screenshot:

- Dimensions: `2868 x 1320`
- Size: `365,220` bytes
- SHA-256: `90169614dd95762fbc262ab12655fa77101cd254661dff7035c9cbaf04c93a6e`

Private console log:

- Size: `5,003` bytes
- SHA-256: `d759f7d2520a62392619e18a34db775c17eeb7d2556bb71381c1e9363dd5ff21`

The private log contains no licensed archive contents. It records only runtime console output, source-path identifiers, line numbers, and compiler diagnostics.

## Proven progression

The physical log confirms all of the following in the M4H candidate:

1. Public `gzdoom.pk3` was mounted.
2. The private user-supplied `Selaco.ipk3` was mounted with `38,002` lumps.
3. Sound initialization completed far enough to continue startup.
4. The engine created a Vulkan device on the Apple A18 Pro GPU.
5. Native resolution was reported as `2868 x 1320`.
6. String loading, machine-state initialization, screen allocation, startup-screen initialization, sound-definition parsing, MAPINFO parsing, and texture-manager initialization completed.
7. `21,447` textures from the licensed archive were indexed.
8. Font, team, and actor-definition initialization began.
9. The earlier `GetSavegameFlags` and `GetSavegameTitle` override errors are absent.
10. ZScript compilation advanced into the retail save-menu scripts.

The terminal app phase was:

```text
phase=m4_engine_probe_returned GameMain returned bounded probe code -1
```

## New reproducible boundary

The private log reports `24` script errors:

- `saveFlags`: 8 unresolved references;
- `info`: 5 unresolved references;
- `elapsedTime`: 3 unresolved references;
- `totaltime`: 3 unresolved references;
- `levelnum`: 2 unresolved references;
- `saveDate`: 2 unresolved references;
- `DoSave`: 1 call with more arguments than the public engine declaration accepts.

Affected licensed-script locations:

- `zscripts/ui/savegames/load_menu.zs`
- `zscripts/ui/savegames/save_menu.zs`
- `zscripts/ui/gwyn_menu/gwyn_menu.zs`

This is a grouped retail save-menu API-contract boundary. It is not a renderer failure, Vulkan failure, native-class-registry failure, or recurrence of the M4F/M4G savegame-override failure.

## Non-blocking warnings

The log also contains five script warnings:

- one duplicate `SpawnBulletDecal` definition, automatically renamed by the engine;
- four unresolved `YellowFlareSmaller` actor references in tracer definitions.

These warnings are not the reason `GameMain()` returned `-1`. They appear after the fatal save-menu compiler errors and should not be remediated under the next bounded save-menu experiment.

## Next bounded experiment

The smallest follow-up must inventory the exact retail save-menu API expected by the licensed scripts before adding compatibility declarations or native behavior.

The next candidate should determine, without copying licensed scripts into Git or CI:

1. the owning public type for each missing member;
2. the required type of `levelnum`, `elapsedTime`, `saveDate`, `info`, `totaltime`, and `saveFlags`;
3. the exact argument count and argument types of the retail `DoSave` call;
4. whether each contract requires a real native implementation or a safe title/menu-only compatibility default.

Do not guess member types, patch the private archive, silence compiler errors globally, or broaden into input, audio, saves, or gameplay.

## Explicit non-claims

This evidence does not yet prove:

- complete licensed ZScript compilation;
- title or menu rendering;
- functional save/load behavior;
- controller input;
- audio output or video playback;
- gameplay;
- lifecycle restoration or performance;
- distribution readiness.
