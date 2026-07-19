#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-app-artifact-probe.sh"
runtime_compile_probe="${repo_root}/scripts/m1-runtime-bootstrap-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m1-runtime-bootstrap-app"
artifact_dir="${repo_root}/build/artifacts/m1-runtime-bootstrap-app"

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
fail_probe() {
  local code="$1"
  local line="$2"
  mkdir -p "${evidence_dir}"
  printf 'FAIL\n' > "${evidence_dir}/result.txt"
  echo "runtime-bootstrap-app-probe: FAIL at line ${line} (exit ${code})"
  exit "${code}"
}
trap cleanup EXIT
trap 'fail_probe $? ${LINENO}' ERR

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

runtime_app="${artifact_dir}/Selaco-runtime-bootstrap-unsigned.app"
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

bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${runtime_app}/Info.plist")"
if [[ "${bundle_identifier}" != "am.arjunkl.selacoios.runtime.m1" ]]; then
  echo "error: unexpected runtime bootstrap bundle identifier: ${bundle_identifier}" >&2
  exit 1
fi

ipa_stage="${workdir}/ipa-stage"
mkdir -p "${ipa_stage}/Payload"
cp -R "${runtime_app}" "${ipa_stage}/Payload/Selaco.app"
runtime_ipa="${artifact_dir}/Selaco-runtime-bootstrap-unsigned.ipa"
(
  cd "${ipa_stage}"
  ditto -c -k --sequesterRsrc Payload "${runtime_ipa}"
)

if ! unzip -Z1 "${runtime_ipa}" | grep -Fxq 'Payload/Selaco.app/Selaco'; then
  echo "error: unsigned IPA lacks Payload/Selaco.app/Selaco" >&2
  exit 1
fi
if unzip -Z1 "${runtime_ipa}" | grep -Eiq '\.(mobileprovision|p12)$'; then
  echo "error: unsigned IPA unexpectedly contains signing material" >&2
  exit 1
fi

ipa_sha256="$(shasum -a 256 "${runtime_ipa}" | awk '{print $1}')"
ipa_size="$(stat -f '%z' "${runtime_ipa}")"
printf '%s  %s\n' "${ipa_sha256}" "$(basename "${runtime_ipa}")" | tee "${evidence_dir}/ipa-sha256.txt"
echo "ipa_size=${ipa_size}" | tee "${evidence_dir}/ipa-size.txt"
unzip -Z1 "${runtime_ipa}" > "${evidence_dir}/ipa-contents.txt"

echo "runtime_status_ui=embedded" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_result_file=Documents/Selaco/runtime-bootstrap.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_identifier=${bundle_identifier}" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa=Selaco-runtime-bootstrap-unsigned.ipa" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_sha256=${ipa_sha256}" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_size=${ipa_size}" >> "${evidence_dir}/probe-manifest.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "runtime-bootstrap-app-probe: PASS"
