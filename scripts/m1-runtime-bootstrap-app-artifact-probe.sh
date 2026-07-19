#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-app-artifact-probe.sh"
runtime_compile_probe="${repo_root}/scripts/m1-runtime-bootstrap-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m1-runtime-bootstrap-app"

for required_file in "${source_probe}" "${runtime_compile_probe}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: runtime bootstrap app input is missing: ${required_file}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m1-runtime-bootstrap-app-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

text = text.replace(
    "build/evidence/m0-full-engine-app",
    "build/evidence/m1-runtime-bootstrap-app",
)
text = text.replace(
    "build/artifacts/m0-full-engine-app",
    "build/artifacts/m1-runtime-bootstrap-app",
)
text = text.replace(
    "build/work/m0-full-engine-app",
    "build/work/m1-runtime-bootstrap-app",
)
text = text.replace(
    'compile_probe="${repo_root}/scripts/m0-full-engine-compile-probe.sh"',
    'compile_probe="${repo_root}/scripts/m1-runtime-bootstrap-compile-probe.sh"',
    1,
)
text = text.replace(
    "build/evidence/m0-full-engine-compile",
    "build/evidence/m1-runtime-bootstrap-compile",
)
text = text.replace(
    "Selaco-full-engine-unsigned",
    "Selaco-runtime-bootstrap-unsigned",
)
text = text.replace(
    "full-engine-app-probe:",
    "runtime-bootstrap-app-probe:",
)
text = text.replace(
    "for retained_symbol in _main _Args _Video _PerfToSec; do",
    "for retained_symbol in _main _UIApplicationMain _Args _Video _PerfToSec; do",
    1,
)
text = text.replace(
    "physical_execution=not_tested\n",
    "runtime_lifecycle=uikit_embedded_not_executed\n"
    "vulkan_metal_probe=embedded_not_executed\n"
    "physical_execution=not_tested\n",
    1,
)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"

runtime_app="${repo_root}/build/artifacts/m1-runtime-bootstrap-app/Selaco-runtime-bootstrap-unsigned.app"
runtime_executable="${runtime_app}/Selaco"
if [[ ! -f "${runtime_executable}" ]]; then
  echo "error: runtime bootstrap executable was not preserved" >&2
  exit 1
fi

strings "${runtime_executable}" > "${evidence_dir}/runtime-strings.txt"
if ! grep -Fq 'SelacoiOS Runtime Bootstrap' "${evidence_dir}/runtime-strings.txt"; then
  echo "error: final executable lacks the runtime-bootstrap status marker" >&2
  exit 1
fi
if ! grep -Fq 'No swapchain or game loop started' "${evidence_dir}/runtime-strings.txt"; then
  echo "error: final executable lacks the bounded runtime stop marker" >&2
  exit 1
fi

echo "runtime_status_ui=embedded" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_result_file=Documents/Selaco/runtime-bootstrap.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "runtime-bootstrap-app-probe: PASS"
