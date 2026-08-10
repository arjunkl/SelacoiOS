#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4j-savegame-context-diagnostics-app-artifact-probe.sh"
compile_probe="${repo_root}/scripts/m4l-savegame-receiver-compile-probe.sh"

for required in "${source_probe}" "${compile_probe}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4L app prerequisite is missing: ${required}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m4l-savegame-receiver-diagnostics-app-artifact-probe.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

text = text.replace(
    "m4j-savegame-context-compile-probe.sh",
    "m4l-savegame-receiver-compile-probe.sh",
)
text = text.replace(
    "build/evidence/m4j-savegame-context-compile",
    "build/evidence/m4l-savegame-receiver-compile",
)

old_markers = r"""  'SELACO_IOS_M4J identifier=' \\
  'parent_chain=' \\
  'usage=' \\
  'expected_type=' \\
  'SELACO_IOS_M4J_DOSAVE_ADAPTER' \\
  'SELACO_IOS_M4J_DOSAVE_NO_WRITE' \\
  'write_attempted=0' \\
  'zscript-compile.log' \\
"""
new_markers = r"""  'SELACO_IOS_M4L_UNKNOWN_MEMBER' \\
  'parent_chain=' \\
  'usage=' \\
  'expected_type=' \\
  'receiver_type=' \\
  'receiver_kind=' \\
  'requested_member=' \\
  'SELACO_IOS_M4J_DOSAVE_ADAPTER' \\
  'SELACO_IOS_M4J_DOSAVE_NO_WRITE' \\
  'write_attempted=0' \\
  'zscript-compile.log' \\
"""
if text.count(old_markers) != 1:
    raise SystemExit("M4L predecessor runtime-marker list changed")
text = text.replace(old_markers, new_markers, 1)

proof_end = (
    'echo "checkpoint=no_write_source_proof_validated" '
    '>> "${checkpoint_file}"\n'
    "'''\n"
)
m4l_validation = r'''echo "checkpoint=no_write_source_proof_validated" >> "${checkpoint_file}"

unzip -p "${public_support}" \
  zscript/compatibility.zs \
  > "${evidence_dir}/m4l-public-compatibility.zs"
for field in levelnum elapsedTime saveDate totaltime saveFlags; do
  if grep -Fq "transient int ${field};" \
    "${evidence_dir}/m4l-public-compatibility.zs"; then
    echo "error: invalid M4K Object field ${field} was packaged" >&2
    exit 1
  fi
done
grep -Fq \
  'SELACO_IOS_M4L: M4K Object fields removed' \
  "${evidence_dir}/m4l-public-compatibility.zs"
echo "checkpoint=m4l_object_surface_removed" >> "${checkpoint_file}"

compile_patch="${repo_root}/build/evidence/m4l-savegame-receiver-compile/applied-gzselaco-ios.patch"
python3 - \
  "${compile_patch}" \
  "${evidence_dir}/m4l-receiver-proof.txt" \
  <<'PYM4LPROOF'
from __future__ import annotations

import pathlib
import sys

patch = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
proof = pathlib.Path(sys.argv[2])

required = (
    "SELACO_IOS_SAVEGAME_RECEIVER_DIAGNOSTICS=1",
    "SELACO_IOS_M4L_UNKNOWN_MEMBER",
    "receiver_type=%s",
    "receiver_kind=%s",
    "requested_member=%s",
    "SelacoIOSM4LRequestedMember",
    "ScriptPosition, Identifier, ctx, this, objtype",
    "SELACO_IOS_M4J_DOSAVE_ADAPTER",
    "DEFINE_ACTION_FUNCTION(FSavegameManager, SelacoIOSM4JDoSaveDiagnostic)",
)
for needle in required:
    if needle not in patch:
        raise SystemExit(f"M4L generated patch missing {needle}")

for forbidden in (
    "SELACO_IOS_SAVEGAME_COMPAT_DIAGNOSTICS=1",
    "SELACO_IOS_M4K_COMPAT field=",
    "+\ttransient int levelnum;",
    "+\ttransient int elapsedTime;",
    "+\ttransient int saveDate;",
    "+\ttransient int totaltime;",
    "+\ttransient int saveFlags;",
    "SELACO_IOS_M4K_SAVE_BLOCKED",
):
    if forbidden in patch:
        raise SystemExit(f"M4L final source retains forbidden M4K surface: {forbidden}")

for deleted in (
    "-DEFINE_ACTION_FUNCTION(FSavegameManager, DoSave)",
    "-\tPARAM_SELF_STRUCT_PROLOGUE(FSavegameManagerBase);",
    "-\tPARAM_INT(sel);",
    "-\tPARAM_STRING(name);",
    "-\tself->DoSave(sel, name.GetChars());",
):
    if deleted in patch:
        raise SystemExit(f"original two-argument DoSave thunk changed: {deleted}")

proof.write_text(
    "diagnostic_scope=receiver_type_and_requested_member\n"
    "Object_fields_added=no\n"
    "SaveGameNode_fields_added=no\n"
    "retail_UI_fields_added=no\n"
    "M4K_compatibility_macro_enabled=no\n"
    "M4K_broad_save_guards_enabled=no\n"
    "M4J_exact_three_argument_adapter_retained=yes\n"
    "save_write_path_called_by_adapter=no\n"
    "expected_member_misses=15\n"
    "expected_bare_misses=8\n",
    encoding="utf-8",
)
PYM4LPROOF
echo "checkpoint=m4l_receiver_diagnostics_validated" \
  >> "${checkpoint_file}"
'''
if text.count(proof_end) != 1:
    raise SystemExit("M4L predecessor no-write validation terminator changed")
text = text.replace(proof_end, m4l_validation + "'''\n", 1)

text = text.replace(
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.8.0'",
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.8.2'",
)
text = text.replace(
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 17'",
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 19'",
)
text = text.replace(
    '"${short_version}" != "0.8.0" || "${build_version}" != "17"',
    '"${short_version}" != "0.8.2" || "${build_version}" != "19"',
)
text = text.replace(
    "m4j_savegame_context_diagnostics=ast_context_parent_chain_and_no_write_values",
    "m4l_savegame_receiver_diagnostics=receiver_type_requested_member_and_exact_no_write_adapter",
)
text = text.replace(
    "m4j-savegame-context-diagnostics-app-probe: PASS",
    "m4l-savegame-receiver-diagnostics-app-probe: PASS",
)

finalize_marker = 'destination.write_text(text, encoding="utf-8")\n'
finalize_replacement = r'''text = text.replace(
    '  echo "diagnostic_DoSave_recoverable_abort=yes"\n',
    '  echo "diagnostic_DoSave_recoverable_abort=yes"\n'
    '  echo "receiver_diagnostics=receiver_type,receiver_kind,requested_member"\n'
    '  echo "compatibility_fields_added=no"\n'
    '  echo "m4k_broad_guards_enabled=no"\n',
)
text = text.replace("m4j-ipa-", "m4l-ipa-")
text = text.replace("M4J IPA contains", "M4L IPA contains")
text = text.replace(
    'echo "checkpoint=m4j_package_passed"',
    'echo "checkpoint=m4l_package_passed"',
)
'''
if text.count(finalize_marker) != 1:
    raise SystemExit("M4L predecessor final-driver writer changed")
text = text.replace(
    finalize_marker,
    finalize_replacement + finalize_marker,
    1,
)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${driver}"
if [[ "${SELACOIOS_GENERATE_ONLY:-0}" == "1" ]]; then
  echo "m4l-savegame-receiver-diagnostics-app-probe: generated driver syntax PASS"
  exit 0
fi
bash "${driver}"
