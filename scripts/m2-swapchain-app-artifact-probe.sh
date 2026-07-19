#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-app-artifact-probe.sh"
swapchain_compile_probe="${repo_root}/scripts/m2-swapchain-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m2-swapchain-app"
artifact_dir="${repo_root}/build/artifacts/m2-swapchain-app"

for required_file in "${source_probe}" "${swapchain_compile_probe}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: Milestone 2 app input is missing: ${required_file}" >&2
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
  echo "swapchain-app-probe: FAIL at line ${line} (exit ${code})"
  exit "${code}"
}
trap cleanup EXIT
trap 'fail_probe $? ${LINENO}' ERR

driver="${workdir}/m2-swapchain-app-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

text = text.replace(
    "build/evidence/m0-full-engine-app",
    "build/evidence/m2-swapchain-app",
)
text = text.replace(
    "build/artifacts/m0-full-engine-app",
    "build/artifacts/m2-swapchain-app",
)
text = text.replace(
    "build/work/m0-full-engine-app",
    "build/work/m2-swapchain-app",
)
text = text.replace(
    'compile_probe="${repo_root}/scripts/m0-full-engine-compile-probe.sh"',
    'compile_probe="${repo_root}/scripts/m2-swapchain-compile-probe.sh"',
    1,
)
text = text.replace(
    "build/evidence/m0-full-engine-compile",
    "build/evidence/m2-swapchain-compile",
)
text = text.replace(
    "Selaco-full-engine-unsigned",
    "Selaco-swapchain-clear-frame-unsigned",
)
text = text.replace(
    "full-engine-app-probe:",
    "swapchain-app-probe:",
)
text = text.replace(
    "for retained_symbol in _main _Args _Video _PerfToSec; do",
    "for retained_symbol in _main _UIApplicationMain _Args _Video _PerfToSec; do",
    1,
)
text = text.replace(
    "physical_execution=not_tested\n",
    "runtime_lifecycle=uikit_swapchain_presenter_not_executed\n"
    "vulkan_loader=volk_custom_dynamic_framework_not_executed\n"
    "logical_device=embedded_not_executed\n"
    "swapchain_clear_frame=embedded_not_executed\n"
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
plist_closure = r'''python3 - "${info_plist}" <<'SWAPCHAIN_PLIST'
from __future__ import annotations

import pathlib
import plistlib
import sys

plist_path = pathlib.Path(sys.argv[1])
with plist_path.open("rb") as stream:
    info = plistlib.load(stream)

info.update({
    "CFBundleIdentifier": "am.arjunkl.selacoios.swapchain.m2",
    "CFBundleName": "SelacoiOS Swapchain",
    "CFBundleDisplayName": "SelacoiOS Swapchain",
    "CFBundleShortVersionString": "0.4.0",
    "CFBundleVersion": "4",
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
SWAPCHAIN_PLIST

'''
text = text.replace(validation_marker, plist_closure + validation_marker, 1)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"

swapchain_app="${artifact_dir}/Selaco-swapchain-clear-frame-unsigned.app"
swapchain_executable="${swapchain_app}/Selaco"
moltenvk_framework="${swapchain_app}/Frameworks/MoltenVK.framework"
moltenvk_binary="${moltenvk_framework}/MoltenVK"
if [[ ! -f "${swapchain_executable}" ]]; then
  echo "error: Milestone 2 executable was not preserved" >&2
  exit 1
fi
if [[ ! -f "${moltenvk_binary}" ]]; then
  echo "error: Milestone 2 app lacks embedded MoltenVK.framework" >&2
  exit 1
fi

strings "${swapchain_executable}" > "${evidence_dir}/runtime-strings.txt"
for required_marker in \
  'SelacoiOS Milestone 2' \
  'vkCreateSwapchainKHR' \
  'vkQueuePresentKHR' \
  'phase=m2_first_frame_presented' \
  'No GZSelaco game loop started'; do
  if ! grep -Fq "${required_marker}" "${evidence_dir}/runtime-strings.txt"; then
    echo "error: final executable lacks Milestone 2 marker: ${required_marker}" >&2
    exit 1
  fi
done

file "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-file.txt"
xcrun lipo -info "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-architecture.txt"
xcrun vtool -show-build "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-build-version.txt"
otool -D "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-install-name.txt"
otool -L "${swapchain_executable}" | tee "${evidence_dir}/runtime-linked-libraries.txt"
if ! grep -Fq '@rpath/MoltenVK.framework/MoltenVK' "${evidence_dir}/runtime-linked-libraries.txt"; then
  echo "error: Milestone 2 executable is not linked to embedded MoltenVK.framework" >&2
  exit 1
fi

bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${swapchain_app}/Info.plist")"
if [[ "${bundle_identifier}" != "am.arjunkl.selacoios.swapchain.m2" ]]; then
  echo "error: unexpected Milestone 2 bundle identifier: ${bundle_identifier}" >&2
  exit 1
fi

ipa_stage="${workdir}/ipa-stage"
mkdir -p "${ipa_stage}/Payload"
cp -R "${swapchain_app}" "${ipa_stage}/Payload/Selaco.app"
swapchain_ipa="${artifact_dir}/Selaco-swapchain-clear-frame-unsigned.ipa"
(
  cd "${ipa_stage}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${swapchain_ipa}"
)

unzip -Z1 "${swapchain_ipa}" > "${evidence_dir}/ipa-contents.txt"
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

ipa_sha256="$(shasum -a 256 "${swapchain_ipa}" | awk '{print $1}')"
ipa_size="$(stat -f '%z' "${swapchain_ipa}")"
printf '%s  %s\n' "${ipa_sha256}" "$(basename "${swapchain_ipa}")" | tee "${evidence_dir}/ipa-sha256.txt"
echo "ipa_size=${ipa_size}" | tee "${evidence_dir}/ipa-size.txt"

echo "runtime_status_ui=swapchain_clear_frame_overlay" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_breadcrumb_file=Documents/Selaco/runtime-bootstrap.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_status_file=Documents/Selaco/swapchain-status.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_identifier=${bundle_identifier}" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_version=0.4.0(4)" >> "${evidence_dir}/probe-manifest.txt"
echo "moltenvk_linkage=dynamic_embedded_framework" >> "${evidence_dir}/probe-manifest.txt"
echo "volk_initialization=custom_from_embedded_vkGetInstanceProcAddr" >> "${evidence_dir}/probe-manifest.txt"
echo "present_mode=FIFO" >> "${evidence_dir}/probe-manifest.txt"
echo "clear_frame=recorded_not_executed" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa=Selaco-swapchain-clear-frame-unsigned.ipa" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_sha256=${ipa_sha256}" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_size=${ipa_size}" >> "${evidence_dir}/probe-manifest.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "swapchain-app-probe: PASS"
