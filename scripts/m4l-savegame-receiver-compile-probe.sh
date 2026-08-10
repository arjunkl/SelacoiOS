#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4j-savegame-context-compile-probe.sh"
m4k_patcher="${repo_root}/scripts/patch-gzselaco-savegame-compat-ios-m4k.py"
m4l_patcher="${repo_root}/scripts/patch-gzselaco-savegame-receiver-diagnostics-ios-m4l.py"

for required in "${source_probe}" "${m4k_patcher}" "${m4l_patcher}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4L compile prerequisite is missing: ${required}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m4l-savegame-receiver-compile-probe.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

variable_marker = (
    'm4j_patcher="${repo_root}/scripts/'
    'patch-gzselaco-savegame-context-diagnostics-ios-m4j.py"\n'
)
variable_replacement = variable_marker + (
    'm4k_patcher="${repo_root}/scripts/'
    'patch-gzselaco-savegame-compat-ios-m4k.py"\n'
    'm4l_patcher="${repo_root}/scripts/'
    'patch-gzselaco-savegame-receiver-diagnostics-ios-m4l.py"\n'
)
if text.count(variable_marker) != 1:
    raise SystemExit("M4L predecessor patcher-variable marker changed")
text = text.replace(variable_marker, variable_replacement, 1)

required_marker = 'for required in "${source_probe}" "${m4j_patcher}"; do\n'
required_replacement = (
    'for required in "${source_probe}" "${m4j_patcher}" '
    '"${m4k_patcher}" "${m4l_patcher}"; do\n'
)
if text.count(required_marker) != 1:
    raise SystemExit("M4L predecessor required-input marker changed")
text = text.replace(required_marker, required_replacement, 1)

patch_marker = r'''    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-context-diagnostics-ios-m4j.py\\" "
    "\\"${source_dir}\\"\\\\n',\\n"
'''
patch_replacement = r'''    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-context-diagnostics-ios-m4j.py\\" "
    "\\"${source_dir}\\"\\\\n'\\n"
    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-compat-ios-m4k.py\\" "
    "\\"${source_dir}\\"\\\\n'\\n"
    "    + 'python3 \\"${repo_root}/scripts/patch-gzselaco-savegame-receiver-diagnostics-ios-m4l.py\\" "
    "\\"${source_dir}\\"\\\\n',\\n"
'''
if text.count(patch_marker) != 1:
    raise SystemExit("M4L predecessor patch-chain marker changed")
text = text.replace(patch_marker, patch_replacement, 1)

text = text.replace(
    "build/evidence/m4j-savegame-context-compile",
    "build/evidence/m4l-savegame-receiver-compile",
)
text = text.replace(
    "generated-m4j-savegame-context-compile-driver.sh",
    "generated-m4l-savegame-receiver-compile-driver.sh",
)
text = text.replace(
    "m4j-savegame-context-compile-probe:",
    "m4l-savegame-receiver-compile-probe:",
)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${driver}"
if [[ "${SELACOIOS_GENERATE_ONLY:-0}" == "1" ]]; then
  echo "m4l-savegame-receiver-compile-probe: generated driver syntax PASS"
  exit 0
fi
bash "${driver}"
