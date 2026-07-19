# SelacoiOS

SelacoiOS is an experimental, community-driven effort to investigate and build a native iOS port of the open-source GZSelaco engine for use with a legally obtained copy of **Selaco**.

## Current status

The project is in **Milestone 0: static feasibility and architecture validation**. No claim of a working iOS build, successful launch, gameplay, packaging, or device validation should be inferred until reproducible evidence is committed or linked from this repository.

The active source revision and automated assumptions are recorded in [`SOURCE_PIN.env`](SOURCE_PIN.env). The bootstrap CI checks the repository asset boundary and audits that exact upstream revision.

## Legal and asset boundary

This repository must not contain Selaco's proprietary game data, including `Selaco.ipk3`, commercial artwork, audio, maps, videos, or other assets extracted from a purchased installation.

The intended eventual workflow is an engine-only iOS application that imports game data supplied by the user from their own legally obtained copy. Engine source and modifications will be handled under the applicable open-source licences. Selaco names and trademarks remain the property of their respective owners.

This project is not affiliated with or endorsed by Altered Orbit Studios, Fulqrum Publishing, the GZDoom team, or Apple.

## Initial technical direction

- Target: physical arm64 iPhone, initially an iPhone 16 Pro Max / A18 Pro
- Renderer: Vulkan through MoltenVK, subject to physical-device validation
- Input: external controller first; touch and gyro after engine viability is proven
- Data: user-imported `Selaco.ipk3`; never committed or bundled
- Delivery: private development IPA during validation; no public distribution assumptions

## Project evidence

- [`docs/PROJECT_COMMAND_CENTRE.md`](docs/PROJECT_COMMAND_CENTRE.md): scope, evidence status, milestone gates, and stop conditions
- [`docs/M0_DEPENDENCY_AND_PLATFORM_AUDIT.md`](docs/M0_DEPENDENCY_AND_PLATFORM_AUDIT.md): initial dependency closure and Apple-versus-iOS source audit

Development work proceeds through evidence-gated milestones rather than broad speculative implementation.
