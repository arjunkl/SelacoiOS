#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4j-savegame-context-diagnostics-app-artifact-probe.sh"
compile_probe="${repo_root}/scripts/m4k-savegame-compat-compile-probe.sh"

for required in "${source_probe}" "${compile_probe}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4K app prerequisite is missing: ${required}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m4k-savegame-compat-app-artifact-probe.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

text = text.replace(
    "m4j-savegame-context-compile-probe.sh",
    "m4k-savegame-compat-compile-probe.sh",
)
text = text.replace(
    "build/evidence/m4j-savegame-context-compile",
    "build/evidence/m4k-savegame-compat-compile",
)

old_markers = r"""  'SELACO_IOS_M4J_DOSAVE_NO_WRITE' \\
  'write_attempted=0' \\
  'zscript-compile.log' \\
"""
new_markers = r"""  'SELACO_IOS_M4J_DOSAVE_NO_WRITE' \\
  'write_attempted=0' \\
  'SELACO_IOS_M4K_COMPAT field=' \\
  'SELACO_IOS_M4K_SAVE_BLOCKED' \\
  'zscript-compile.log' \\
"""
if text.count(old_markers) != 1:
    raise SystemExit("M4K predecessor runtime-marker list changed")
text = text.replace(old_markers, new_markers, 1)

proof_end = (
    'echo "checkpoint=no_write_source_proof_validated" '
    '>> "${checkpoint_file}"\n'
    "'''\n"
)
m4k_validation = r'''echo "checkpoint=no_write_source_proof_validated" >> "${checkpoint_file}"

unzip -p "${public_support}" \
  zscript/compatibility.zs \
  > "${evidence_dir}/m4k-public-compatibility.zs"
for field in levelnum elapsedTime saveDate totaltime saveFlags; do
  grep -Fq \
    "SELACO_IOS_M4K_COMPAT field=${field} owner=Object type=SInt4 source=diagnostic-default default=0 read_only=0 persisted=0" \
    "${evidence_dir}/m4k-public-compatibility.zs"
  grep -Fq "transient int ${field};" \
    "${evidence_dir}/m4k-public-compatibility.zs"
done
if grep -Fq 'SELACO_IOS_M4K_COMPAT field=info' \
  "${evidence_dir}/m4k-public-compatibility.zs"; then
  echo "error: ambiguous info compatibility field was packaged" >&2
  exit 1
fi
echo "checkpoint=m4k_transient_compatibility_surface_validated" \
  >> "${checkpoint_file}"

compile_patch="${repo_root}/build/evidence/m4k-savegame-compat-compile/applied-gzselaco-ios.patch"
python3 - "${compile_patch}" "${evidence_dir}/m4k-no-write-proof.txt" <<'PYM4KPROOF'
from __future__ import annotations

import pathlib
import sys

patch = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
proof = pathlib.Path(sys.argv[2])

required = (
    "SELACO_IOS_M4K_COMPAT field=levelnum",
    "SELACO_IOS_M4K_COMPAT field=elapsedTime",
    "SELACO_IOS_M4K_COMPAT field=saveDate",
    "SELACO_IOS_M4K_COMPAT field=totaltime",
    "SELACO_IOS_M4K_COMPAT field=saveFlags",
    "path=SavegameManager.RemoveSaveSlot",
    "path=SavegameManager.DoSave",
    "path=G_SaveGame",
    "path=G_DoSaveGame",
)
for needle in required:
    if needle not in patch:
        raise SystemExit(f"M4K generated patch missing {needle}")

for deleted in (
    "-DEFINE_ACTION_FUNCTION(FSavegameManager, DoSave)",
    "-\tPARAM_SELF_STRUCT_PROLOGUE(FSavegameManagerBase);",
    "-\tPARAM_INT(sel);",
    "-\tPARAM_STRING(name);",
    "-\tself->DoSave(sel, name.GetChars());",
):
    if deleted in patch:
        raise SystemExit(f"original two-argument DoSave thunk changed: {deleted}")

if "SELACO_IOS_M4K_COMPAT field=info" in patch:
    raise SystemExit("ambiguous info field unexpectedly introduced")
if "+class SavegameSlotControl" in patch or "+class SavegameSlotControl :" in patch:
    raise SystemExit("retail SavegameSlotControl hierarchy was modified")

guard_order = {
    "SavegameManager.RemoveSaveSlot": (
        "path=SavegameManager.RemoveSaveSlot",
        "RemoveFile(",
    ),
    "SavegameManager.DoSave": (
        "path=SavegameManager.DoSave",
        "PerformSaveGame(",
    ),
    "G_SaveGame": ("path=G_SaveGame", "sendsave = true"),
    "G_DoSaveGame": ("path=G_DoSaveGame", "savegame_content"),
}
for name, (guard, write_boundary) in guard_order.items():
    start = patch.find(guard)
    if start < 0:
        raise SystemExit(f"{name} guard missing")
    boundary = patch.find(write_boundary, start)
    if boundary < 0:
        raise SystemExit(f"{name} downstream boundary missing")
    abort = patch.find("I_Error(", start, boundary)
    if abort < 0:
        raise SystemExit(f"{name} guard does not abort before {write_boundary}")

proof.write_text(
    "compatibility_owner=Object\n"
    "compatibility_type=SInt4\n"
    "compatibility_storage=transient\n"
    "compatibility_default=0\n"
    "compatibility_persisted=no\n"
    "info_declared=no\n"
    "SavegameSlotControl_hierarchy_changed=no\n"
    "original_two_argument_DoSave_changed=no\n"
    "three_argument_adapter_calls_real_save=no\n"
    "RemoveSaveSlot_aborts_before_RemoveFile=yes\n"
    "SavegameManager_DoSave_aborts_before_PerformSaveGame=yes\n"
    "G_SaveGame_aborts_before_save_scheduling=yes\n"
    "G_DoSaveGame_aborts_before_snapshot_or_serialization=yes\n"
    "new_save_metadata_keys=no\n",
    encoding="utf-8",
)
PYM4KPROOF
echo "checkpoint=m4k_structural_no_write_guards_validated" \
  >> "${checkpoint_file}"
'''
if text.count(proof_end) != 1:
    raise SystemExit("M4K predecessor no-write validation terminator changed")
text = text.replace(proof_end, m4k_validation + "'''\n", 1)

text = text.replace(
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.8.0'",
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.8.1'",
)
text = text.replace(
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 17'",
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 18'",
)
text = text.replace(
    '"${short_version}" != "0.8.0" || "${build_version}" != "17"',
    '"${short_version}" != "0.8.1" || "${build_version}" != "18"',
)
text = text.replace(
    "m4j_savegame_context_diagnostics=ast_context_parent_chain_and_no_write_values",
    "m4k_savegame_compat=transient_integer_surface_info_blocked_and_no_write",
)
text = text.replace(
    "m4j-savegame-context-diagnostics-app-probe: PASS",
    "m4k-savegame-compat-app-probe: PASS",
)

finalize_marker = 'destination.write_text(text, encoding="utf-8")\n'
finalize_replacement = r'''text = text.replace(
    '  echo "diagnostic_DoSave_recoverable_abort=yes"\n',
    '  echo "diagnostic_DoSave_recoverable_abort=yes"\n'
    '  echo "compatibility_owner=Object"\n'
    '  echo "compatibility_fields=levelnum,elapsedTime,saveDate,totaltime,saveFlags"\n'
    '  echo "compatibility_storage=transient"\n'
    '  echo "compatibility_default=0"\n'
    '  echo "compatibility_persisted=no"\n'
    '  echo "info_declared=no"\n'
    '  echo "global_save_guard=enabled"\n',
)
text = text.replace("m4j-ipa-", "m4k-ipa-")
text = text.replace("M4J IPA contains", "M4K IPA contains")
text = text.replace(
    'echo "checkpoint=m4j_package_passed"',
    'echo "checkpoint=m4k_package_passed"',
)
'''
if text.count(finalize_marker) != 1:
    raise SystemExit("M4K predecessor final-driver writer changed")
text = text.replace(
    finalize_marker,
    finalize_replacement + finalize_marker,
    1,
)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"
