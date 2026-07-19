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
    "runtime_lifecycle=uikit_first_dynamic_moltenvk_not_executed\n"
    "vulkan_loader=volk_custom_dynamic_framework_not_executed\n"
    "vulkan_metal_probe=delayed_breadcrumbed_not_executed\n"
    "physical_execution=not_tested\n",
    1,
)

dependency_marker = '    if dependency.startswith(("/System/Library/", "/usr/lib/")):\n        continue\n'
if text.count(dependency_marker) != 1:
    raise SystemExit("Milestone 0 dynamic-dependency validator changed")
text = text.replace(
    dependency_marker,
    dependency_marker
    + '    if dependency == "@rpath/MoltenVK.framework/MoltenVK":\n'
      '        continue\n',
    1,
)

validation_marker = "printf '== Validate full-engine app bundle ==\\n'\n"
if text.count(validation_marker) != 1:
    raise SystemExit("Milestone 0 app probe validation marker changed")
plist_closure = r'''python3 - "${info_plist}" <<'RUNTIME_PLIST'
from __future__ import annotations

import pathlib
import plistlib
import sys

plist_path = pathlib.Path(sys.argv[1])
with plist_path.open("rb") as stream:
    info = plistlib.load(stream)

info.update({
    "CFBundleIdentifier": "am.arjunkl.selacoios.runtime.m1",
    "CFBundleName": "SelacoiOS Diagnostics",
    "CFBundleDisplayName": "SelacoiOS Diagnostics",
    "CFBundleShortVersionString": "0.3.0",
    "CFBundleVersion": "3",
    "UIFileSharingEnabled": True,
    "LSSupportsOpeningDocumentsInPlace": True,
    "UIRequiresFullScreen": True,
    "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
    ],
    "UILaunchScreen": {},
})

with plist_path.open("wb") as stream:
    plistlib.dump(info, stream, fmt=plistlib.FMT_XML, sort_keys=True)
RUNTIME_PLIST

'''
text = text.replace(validation_marker, plist_closure + validation_marker, 1)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"

runtime_app="${artifact_dir}/Selaco-runtime-bootstrap-unsigned.app"
runtime_executable="${runtime_app}/Selaco"
moltenvk_framework="${runtime_app}/Frameworks/MoltenVK.framework"
moltenvk_binary="${moltenvk_framework}/MoltenVK"
if [[ ! -f "${runtime_executable}" ]]; then
  echo "error: runtime bootstrap executable was not preserved" >&2
  exit 1
fi
if [[ ! -f "${moltenvk_binary}" ]]; then
  echo "error: runtime bootstrap app lacks embedded MoltenVK.framework" >&2
  exit 1
fi

strings "${runtime_executable}" > "${evidence_dir}/runtime-strings.txt"
if ! grep -Fq 'SelacoiOS Crash-Localization Build' "${evidence_dir}/runtime-strings.txt"; then
  echo "error: final executable lacks the crash-localization status marker" >&2
  exit 1
fi
if ! grep -Fq 'vulkan_load_dynamic_moltenvk' "${evidence_dir}/runtime-strings.txt"; then
  echo "error: final executable lacks the dynamic MoltenVK breadcrumb" >&2
  exit 1
fi
if ! grep -Fq 'No swapchain or game loop started' "${evidence_dir}/runtime-strings.txt"; then
  echo "error: final executable lacks the bounded runtime stop marker" >&2
  exit 1
fi
if ! grep -Fq 'phase=main_entered' "${evidence_dir}/runtime-strings.txt"; then
  echo "error: final executable lacks the launch breadcrumb marker" >&2
  exit 1
fi

file "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-file.txt"
xcrun lipo -info "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-architecture.txt"
xcrun vtool -show-build "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-build-version.txt"
otool -D "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-install-name.txt"
otool -L "${runtime_executable}" | tee "${evidence_dir}/runtime-linked-libraries.txt"
if ! grep -Fq '@rpath/MoltenVK.framework/MoltenVK' "${evidence_dir}/runtime-linked-libraries.txt"; then
  echo "error: runtime executable is not linked to embedded MoltenVK.framework" >&2
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
  ditto -c -k --sequesterRsrc --keepParent Payload "${runtime_ipa}"
)

unzip -Z1 "${runtime_ipa}" > "${evidence_dir}/ipa-contents.txt"
if ! grep -Fxq 'Payload/Selaco.app/Selaco' "${evidence_dir}/ipa-contents.txt"; then
  echo "error: unsigned IPA lacks Payload/Selaco.app/Selaco" >&2
  exit 1
fi
if ! grep -Fxq 'Payload/Selaco.app/Frameworks/MoltenVK.framework/MoltenVK' "${evidence_dir}/ipa-contents.txt"; then
  echo "error: unsigned IPA lacks embedded MoltenVK.framework" >&2
  exit 1
fi
if grep -Eiq '\.(mobileprovision|p12)$' "${evidence_dir}/ipa-contents.txt"; then
  echo "error: unsigned IPA unexpectedly contains signing material" >&2
  exit 1
fi

ipa_sha256="$(shasum -a 256 "${runtime_ipa}" | awk '{print $1}')"
ipa_size="$(stat -f '%z' "${runtime_ipa}")"
printf '%s  %s\n' "${ipa_sha256}" "$(basename "${runtime_ipa}")" | tee "${evidence_dir}/ipa-sha256.txt"
echo "ipa_size=${ipa_size}" | tee "${evidence_dir}/ipa-size.txt"

echo "runtime_status_ui=uikit_first_dynamic_moltenvk" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_result_file=Documents/Selaco/runtime-bootstrap.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_identifier=${bundle_identifier}" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_version=0.3.0(3)" >> "${evidence_dir}/probe-manifest.txt"
echo "moltenvk_linkage=dynamic_embedded_framework" >> "${evidence_dir}/probe-manifest.txt"
echo "volk_initialization=custom_from_embedded_vkGetInstanceProcAddr" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa=Selaco-runtime-bootstrap-unsigned.ipa" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_sha256=${ipa_sha256}" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_size=${ipa_size}" >> "${evidence_dir}/probe-manifest.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "runtime-bootstrap-app-probe: PASS"
