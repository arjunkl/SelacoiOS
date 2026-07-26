#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4i-savegame-api-diagnostics-app-artifact-probe.sh"
compile_probe="${repo_root}/scripts/m4j-savegame-context-compile-probe.sh"

for required in "${source_probe}" "${compile_probe}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4J app prerequisite is missing: ${required}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m4j-savegame-context-diagnostics-app-artifact-probe.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

text = text.replace(
    "m4i-savegame-api-compile-probe.sh",
    "m4j-savegame-context-compile-probe.sh",
)
text = text.replace(
    "build/evidence/m4i-savegame-api-compile",
    "build/evidence/m4j-savegame-context-compile",
)

old_count = '''if text.count(compile_old) != 1:
    raise SystemExit("M4I title-menu compile-probe marker changed")
text = text.replace(compile_old, compile_new, 1)
'''
new_count = '''if text.count(compile_old) != 2:
    raise SystemExit("M4I title-menu compile-probe marker changed")
text = text.replace(compile_old, compile_new)
'''
if text.count(old_count) != 1:
    raise SystemExit("M4J predecessor compile-marker validator changed")
text = text.replace(old_count, new_count, 1)

text = text.replace("M4I", "M4J").replace("m4i", "m4j")

old_markers = """for marker in \\
  'SELACO_IOS_M4J class=' \\
  'SELACO_IOS_M4J caller_class=' \\
  'actual_count=' \\
  'expected_types=' \\
  'actual_types=' \\
  'zscript-compile.log' \\
  'actor_zscript_compile_entered'; do
"""
new_markers = """for marker in \\
  'SELACO_IOS_M4J identifier=' \\
  'parent_chain=' \\
  'usage=' \\
  'expected_type=' \\
  'SELACO_IOS_M4J_DOSAVE_ADAPTER' \\
  'SELACO_IOS_M4J_DOSAVE_NO_WRITE' \\
  'write_attempted=0' \\
  'zscript-compile.log' \\
  'actor_zscript_compile_entered'; do
"""
if text.count(old_markers) != 1:
    raise SystemExit("M4J predecessor runtime-marker list changed")
text = text.replace(old_markers, new_markers, 1)

signature_checkpoint = (
    'echo "checkpoint=exact_public_signatures_validated" '
    '>> "${checkpoint_file}"\n'
)
support_validation = r'''
unzip -p "${public_support}" \
  zscript/engine/ui/menu/loadsavemenu.zs \
  > "${evidence_dir}/m4j-public-loadsavemenu.zs"
grep -Fqx $'\tnative void DoSave(int Selected, String savegamestring);' \
  "${evidence_dir}/m4j-public-loadsavemenu.zs"
grep -Fq \
  'native void SelacoIOSM4JDoSaveDiagnostic(int Selected, String savegamestring, int diagnosticValue);' \
  "${evidence_dir}/m4j-public-loadsavemenu.zs"
echo "checkpoint=diagnostic_entrypoint_validated" >> "${checkpoint_file}"

compile_patch="${repo_root}/build/evidence/m4j-savegame-context-compile/applied-gzselaco-ios.patch"
python3 - "${compile_patch}" "${evidence_dir}/m4j-no-write-proof.txt" <<'PYPROOF'
from __future__ import annotations

import pathlib
import sys

patch = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
proof = pathlib.Path(sys.argv[2])

for deleted in (
    "-DEFINE_ACTION_FUNCTION(FSavegameManager, DoSave)",
    "-\tPARAM_SELF_STRUCT_PROLOGUE(FSavegameManagerBase);",
    "-\tPARAM_INT(sel);",
    "-\tPARAM_STRING(name);",
    "-\tself->DoSave(sel, name.GetChars());",
):
    if deleted in patch:
        raise SystemExit(f"original two-argument DoSave thunk was modified: {deleted}")

marker = "DEFINE_ACTION_FUNCTION(FSavegameManager, SelacoIOSM4JDoSaveDiagnostic)"
start = patch.find(marker)
if start < 0:
    raise SystemExit("M4J diagnostic DoSave thunk is absent from patch")
end = patch.find("#endif", start)
if end < 0:
    raise SystemExit("M4J diagnostic DoSave thunk has no bounded end")
region = patch[start:end]

required = (
    "PARAM_INT(sel)",
    "PARAM_STRING(name)",
    "PARAM_INT(diagnosticValue)",
    "title_length=",
    "I_Error(",
)
for needle in required:
    if needle not in region:
        raise SystemExit(f"M4J no-write region missing {needle}")

for forbidden in (
    "self->DoSave(",
    "PerformSaveGame(",
    "G_SaveGame(",
    "G_DoSaveGame(",
    "RemoveSaveSlot(",
):
    if forbidden in region:
        raise SystemExit(f"M4J no-write region contains {forbidden}")

proof.write_text(
    "diagnostic_target=SelacoIOSM4JDoSaveDiagnostic\n"
    "logs_selected_slot=yes\n"
    "logs_third_integer=yes\n"
    "logs_title_length=yes\n"
    "recoverable_abort_before_return_to_script=yes\n"
    "original_two_argument_DoSave_deleted_or_replaced=no\n"
    "calls_existing_DoSave=no\n"
    "calls_PerformSaveGame=no\n"
    "calls_G_SaveGame=no\n"
    "calls_G_DoSaveGame=no\n",
    encoding="utf-8",
)
PYPROOF
echo "checkpoint=no_write_source_proof_validated" >> "${checkpoint_file}"
'''
if text.count(signature_checkpoint) != 1:
    raise SystemExit("M4J predecessor signature checkpoint changed")
text = text.replace(
    signature_checkpoint,
    signature_checkpoint + support_validation,
    1,
)

text = text.replace(
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.7.9'",
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.8.0'",
)
text = text.replace(
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 16'",
    "/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 17'",
)
text = text.replace(
    '"${short_version}" != "0.7.9" || "${build_version}" != "16"',
    '"${short_version}" != "0.8.0" || "${build_version}" != "17"',
)
text = text.replace(
    "m4j_savegame_api_diagnostics=ownership_context_and_call_contract",
    "m4j_savegame_context_diagnostics=ast_context_parent_chain_and_no_write_values",
)
text = text.replace(
    "unknown_identifier_fields=class,function,self",
    "unknown_identifier_fields=source,line,class,function,self,parent_chain,node,usage,expected_type",
)
text = text.replace(
    "excess_argument_fields=caller_class,caller_function,target_class,"
    "actual_count,declared_explicit,implicit,expected_types,actual_types",
    "diagnostic_adapter_fields=caller_class,caller_function,target_class,"
    "selected_slot,third_integer,title_length,no_write",
)
text = text.replace(
    '  echo "physical_execution=not_tested"\n',
    '  echo "physical_execution=not_tested"\n'
    '  echo "diagnostic_DoSave_calls_real_DoSave=no"\n'
    '  echo "diagnostic_DoSave_recoverable_abort=yes"\n',
)
text = text.replace(
    "m4j-savegame-api-diagnostics-app-probe: PASS",
    "m4j-savegame-context-diagnostics-app-probe: PASS",
)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"
