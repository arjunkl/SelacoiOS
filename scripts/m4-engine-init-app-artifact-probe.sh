#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-app-artifact-probe.sh"
engine_init_compile_probe="${repo_root}/scripts/m4-engine-init-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m4-engine-init-app"
artifact_dir="${repo_root}/build/artifacts/m4-engine-init-app"

for required_file in "${source_probe}" "${engine_init_compile_probe}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: Milestone 4 app input is missing: ${required_file}" >&2
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
  echo "engine-init-app-probe: FAIL at line ${line} (exit ${code})"
  exit "${code}"
}
trap cleanup EXIT
trap 'fail_probe $? ${LINENO}' ERR

driver="${workdir}/m4-engine-init-app-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

text = text.replace(
    "build/evidence/m0-full-engine-app",
    "build/evidence/m4-engine-init-app",
)
text = text.replace(
    "build/artifacts/m0-full-engine-app",
    "build/artifacts/m4-engine-init-app",
)
text = text.replace(
    "build/work/m0-full-engine-app",
    "build/work/m4-engine-init-app",
)
text = text.replace(
    'compile_probe="${repo_root}/scripts/m0-full-engine-compile-probe.sh"',
    'compile_probe="${repo_root}/scripts/m4-engine-init-compile-probe.sh"',
    1,
)
text = text.replace(
    "build/evidence/m0-full-engine-compile",
    "build/evidence/m4-engine-init-compile",
)
text = text.replace(
    "Selaco-full-engine-unsigned",
    "Selaco-engine-init-probe-unsigned",
)
text = text.replace(
    "full-engine-app-probe:",
    "engine-init-app-probe:",
)
text = text.replace(
    "for retained_symbol in _main _Args _Video _PerfToSec; do",
    "for retained_symbol in _main _UIApplicationMain _Args _Video _PerfToSec _SelacoIOSM4RendererStrategy; do",
    1,
)
text = text.replace(
    "physical_execution=not_tested\n",
    "runtime_lifecycle=uikit_swapchain_plus_m4a_engine_init_not_executed\n"
    "renderer_strategy=stop_before_V_Init2_diagnostic_presenter_remains_owner\n"
    "public_support_archive=gzdoom.pk3_generated_from_pinned_source\n"
    "licensed_asset_delivery=documents_folder_user_supplied_only\n"
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
plist_closure = r'''python3 - "${info_plist}" <<'ENGINE_INIT_PLIST'
from __future__ import annotations

import pathlib
import plistlib
import sys

plist_path = pathlib.Path(sys.argv[1])
with plist_path.open("rb") as stream:
    info = plistlib.load(stream)

info.update({
    "CFBundleIdentifier": "am.arjunkl.selacoios.engineinit.m4",
    "CFBundleName": "SelacoiOS Engine Init",
    "CFBundleDisplayName": "SelacoiOS Engine Init",
    "CFBundleShortVersionString": "0.6.0",
    "CFBundleVersion": "6",
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
ENGINE_INIT_PLIST

'''
text = text.replace(validation_marker, plist_closure + validation_marker, 1)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"

engine_init_app="${artifact_dir}/Selaco-engine-init-probe-unsigned.app"
engine_init_executable="${engine_init_app}/Selaco"
moltenvk_framework="${engine_init_app}/Frameworks/MoltenVK.framework"
moltenvk_binary="${moltenvk_framework}/MoltenVK"
public_support="${engine_init_app}/gzdoom.pk3"

for required_path in "${engine_init_executable}" "${moltenvk_binary}" "${public_support}"; do
  if [[ ! -f "${required_path}" ]]; then
    echo "error: Milestone 4 app is missing required file: ${required_path}" >&2
    exit 1
  fi
done

strings "${engine_init_executable}" > "${evidence_dir}/runtime-strings.txt"
for required_marker in \
  'SelacoiOS Milestone 4' \
  'engine_init_boundary_reached' \
  'engine-init-status.txt' \
  'renderer-init-status.txt' \
  'renderer_creation_deferred' \
  'M4A stop-before-renderer' \
  'V_Init2'; do
  if ! grep -Fq "${required_marker}" "${evidence_dir}/runtime-strings.txt"; then
    echo "error: final executable lacks Milestone 4 marker: ${required_marker}" >&2
    exit 1
  fi
done

if find "${engine_init_app}" -type f \( -iname '*.ipk3' -o -iname '*.mobileprovision' -o -iname '*.p12' \) -print -quit | grep -q .; then
  echo "error: Milestone 4 app unexpectedly contains licensed data or signing material" >&2
  exit 1
fi

file "${public_support}" | tee "${evidence_dir}/public-support-file.txt"
shasum -a 256 "${public_support}" | tee "${evidence_dir}/public-support-sha256.txt"
stat -f 'public_support_size=%z' "${public_support}" | tee "${evidence_dir}/public-support-size.txt"

file "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-file.txt"
xcrun lipo -info "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-architecture.txt"
xcrun vtool -show-build "${moltenvk_binary}" | tee "${evidence_dir}/embedded-moltenvk-build-version.txt"
otool -L "${engine_init_executable}" | tee "${evidence_dir}/runtime-linked-libraries.txt"
if ! grep -Fq '@rpath/MoltenVK.framework/MoltenVK' "${evidence_dir}/runtime-linked-libraries.txt"; then
  echo "error: Milestone 4 executable is not linked to embedded MoltenVK.framework" >&2
  exit 1
fi

bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${engine_init_app}/Info.plist")"
bundle_short_version="$(plutil -extract CFBundleShortVersionString raw "${engine_init_app}/Info.plist")"
bundle_version="$(plutil -extract CFBundleVersion raw "${engine_init_app}/Info.plist")"
if [[ "${bundle_identifier}" != "am.arjunkl.selacoios.engineinit.m4" ]]; then
  echo "error: unexpected Milestone 4 bundle identifier: ${bundle_identifier}" >&2
  exit 1
fi
if [[ "${bundle_short_version}" != "0.6.0" || "${bundle_version}" != "6" ]]; then
  echo "error: unexpected Milestone 4 version/build: ${bundle_short_version} (${bundle_version})" >&2
  exit 1
fi

ipa_stage="${workdir}/ipa-stage"
mkdir -p "${ipa_stage}/Payload"
cp -R "${engine_init_app}" "${ipa_stage}/Payload/Selaco.app"
engine_init_ipa="${artifact_dir}/Selaco-engine-init-probe-unsigned.ipa"
(
  cd "${ipa_stage}"
  ditto -c -k --sequesterRsrc --keepParent Payload "${engine_init_ipa}"
)

unzip -Z1 "${engine_init_ipa}" > "${evidence_dir}/ipa-contents.txt"
for expected_entry in \
  'Payload/Selaco.app/Selaco' \
  'Payload/Selaco.app/gzdoom.pk3' \
  'Payload/Selaco.app/Frameworks/MoltenVK.framework/MoltenVK'; do
  if ! grep -Fxq "${expected_entry}" "${evidence_dir}/ipa-contents.txt"; then
    echo "error: unsigned IPA lacks ${expected_entry}" >&2
    exit 1
  fi
done
if grep -Eiq '(^|/)[^/]+\.ipk3$|\.(mobileprovision|p12)$' "${evidence_dir}/ipa-contents.txt"; then
  echo "error: unsigned IPA unexpectedly contains licensed data or signing material" >&2
  exit 1
fi

ipa_sha256="$(shasum -a 256 "${engine_init_ipa}" | awk '{print $1}')"
ipa_size="$(stat -f '%z' "${engine_init_ipa}")"
printf '%s  %s\n' "${ipa_sha256}" "$(basename "${engine_init_ipa}")" | tee "${evidence_dir}/ipa-sha256.txt"
echo "ipa_size=${ipa_size}" | tee "${evidence_dir}/ipa-size.txt"

echo "runtime_status_ui=swapchain_plus_m4a_engine_initialization" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_engine_file=Documents/Selaco/engine-init-status.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_asset_file=Documents/Selaco/licensed-asset-status.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "persistent_renderer_file=Documents/Selaco/renderer-init-status.txt" >> "${evidence_dir}/probe-manifest.txt"
echo "licensed_asset_expected_path=Documents/Selaco/Selaco.ipk3" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_identifier=${bundle_identifier}" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_version=${bundle_short_version}(${bundle_version})" >> "${evidence_dir}/probe-manifest.txt"
echo "public_support_archive=gzdoom.pk3" >> "${evidence_dir}/probe-manifest.txt"
echo "licensed_asset_bundled=no" >> "${evidence_dir}/probe-manifest.txt"
echo "engine_stop_boundary=immediately_before_V_Init2" >> "${evidence_dir}/probe-manifest.txt"
echo "renderer_ownership=diagnostic_presenter_only" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa=Selaco-engine-init-probe-unsigned.ipa" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_sha256=${ipa_sha256}" >> "${evidence_dir}/probe-manifest.txt"
echo "unsigned_ipa_size=${ipa_size}" >> "${evidence_dir}/probe-manifest.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "engine-init-app-probe: PASS"
