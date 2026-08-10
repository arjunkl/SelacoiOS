# SelacoiOS agent instructions

## Codebase discovery protocol

Use Codebase Memory before broad file-by-file exploration. Treat its graph as a
structural index, not as proof: confirm every proposed runtime change against
the relevant source, CI evidence, and physical-device logs.

SelacoiOS contains patch/build drivers, not a checked-in GZSelaco source tree.
For runtime analysis, materialize the exact cumulatively patched engine with:

```sh
scripts/materialize-codebase-memory-analysis.sh
```

Index both projects:

1. the SelacoiOS repository, for build drivers, patchers, evidence contracts,
   and workflows;
2. `.codebase-memory-worktree/GZSelaco-M4L`, for the actual patched C++/ZScript
   runtime compiled by the latest M4L workflow.

Use `search_graph`, `trace_path`, `get_code_snippet`, and `get_architecture` to
identify entry points, subsystem boundaries, callers/callees, and competing
explanations. Use ordinary source search only to confirm graph findings or to
cover parser/index gaps.

## Investigation discipline

Do not resume serial nearby patching merely because the last failure named a
local symbol. Before each implementation:

1. state the current architectural model;
2. identify evidence that supports and contradicts it;
3. list at least one competing hypothesis;
4. define a device log marker that distinguishes the hypotheses;
5. make the smallest reversible change that can produce that evidence.

Preserve the proprietary-data boundary. Never commit, upload, inspect, or copy
`Selaco.ipk3` or licensed archive contents. Device logs may report archive
identity, lump counts, source-path identifiers, line numbers, and compiler
diagnostics, but not licensed script bodies.

Codebase Memory setup in this repository is project-scoped and intentionally
does not install global hooks or modify user-level Codex configuration.
