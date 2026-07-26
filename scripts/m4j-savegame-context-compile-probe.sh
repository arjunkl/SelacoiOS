#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4i-savegame-api-compile-probe.sh"
m4j_patcher="${repo_root}/scripts/patch-gzselaco-savegame-context-diagnostics-ios-m4j.py"

for required in "${source_probe}" "${m4j_patcher}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4J compile prerequisite is missing: ${required}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m4j-savegame-context-compile-probe.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

variable_marker = (
    'savegame_api_diagnostics_patcher="${repo_root}/scripts/'
    'patch-gzselaco-savegame-api-diagnostics-ios-m4i.py"\n'
)
variable_replacement = variable_marker + (
    'savegame_context_diagnostics_patcher="${repo_root}/scripts/'
    'patch-gzselaco-savegame-context-diagnostics-ios-m4j.py"\n'
)
if text.count(variable_marker) != 1:
    raise SystemExit("M4J predecessor patcher-variable marker changed")
text = text.replace(variable_marker, variable_replacement, 1)

required_marker = '  "${savegame_api_diagnostics_patcher}" \\\n'
required_replacement = (
    required_marker + '  "${savegame_context_diagnostics_patcher}" \\\n'
)
if text.count(required_marker) != 1:
    raise SystemExit("M4J predecessor required-input marker changed")
text = text.replace(required_marker, required_replacement, 1)

patch_marker = '''    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-api-diagnostics-ios-m4i.py\\" "
    "\\"${source_dir}\\"\\\\n',\\n"
'''
patch_replacement = '''    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-api-diagnostics-ios-m4i.py\\" "
    "\\"${source_dir}\\"\\\\n'\\n"
    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-context-diagnostics-ios-m4j.py\\" "
    "\\"${source_dir}\\"\\\\n',\\n"
'''
if text.count(patch_marker) != 1:
    raise SystemExit("M4J predecessor patch-chain marker changed")
text = text.replace(patch_marker, patch_replacement, 1)

text = text.replace(
    "build/evidence/m4i-savegame-api-compile",
    "build/evidence/m4j-savegame-context-compile",
)
text = text.replace(
    "generated-m4i-savegame-api-compile-driver.sh",
    "generated-m4j-savegame-context-compile-driver.sh",
)
text = text.replace(
    "m4i-savegame-api-compile-probe:",
    "m4j-savegame-context-compile-probe:",
)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"
