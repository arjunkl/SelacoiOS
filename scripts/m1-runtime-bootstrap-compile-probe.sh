#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-compile-probe.sh"
runtime_patcher="${repo_root}/scripts/patch-gzselaco-runtime-bootstrap-ios-m1.py"
runtime_overlay="${repo_root}/overlays/gzselaco-ios/i_runtime_bootstrap.mm"
evidence_dir="${repo_root}/build/evidence/m1-runtime-bootstrap-compile"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"

for required_file in "${source_probe}" "${runtime_patcher}" "${runtime_overlay}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: runtime bootstrap compile input is missing: ${required_file}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m1-runtime-bootstrap-compile-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

text = text.replace(
    "build/evidence/m0-full-engine-compile",
    "build/evidence/m1-runtime-bootstrap-compile",
)

old = (
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py\" "
    "\"${source_dir}\"\\n',\n"
)
new = (
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py\" "
    "\"${source_dir}\"\\n'\n"
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-runtime-bootstrap-ios-m1.py\" "
    "\"${source_dir}\"\\n',\n"
)
if text.count(old) != 1:
    raise SystemExit(
        "Milestone 0 compile probe no longer exposes the expected Vulkan patch insertion"
    )
text = text.replace(old, new, 1)
text = text.replace(
    "full-engine-compile-probe:",
    "runtime-bootstrap-compile-probe:",
)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

cp "${driver}" "${evidence_dir}/generated-runtime-compile-driver.sh"
bash -n "${driver}"
bash "${driver}"
