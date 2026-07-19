#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
workdir="$(mktemp -d)"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

artifact_id="8444474531"
expected_outer_sha256="1fbb214318211679740dc46a424547eab05f4d3a12ae7c63996266f85ac33b7f"
expected_inner_sha256="8269e6734b3f99183aa9062f3efb766cf249f8b1e5a1c48e650a516ff08a4bf8"
output_dir="${repo_root}/build/artifacts/m1-runtime-bootstrap-ipa-repack"
evidence_dir="${repo_root}/build/evidence/m1-runtime-bootstrap-ipa-repack"
rm -rf "${output_dir}" "${evidence_dir}"
mkdir -p "${output_dir}" "${evidence_dir}" "${workdir}/outer" "${workdir}/inner" "${workdir}/stage/Payload"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

for command_name in curl unzip shasum python3 file xcrun codesign ditto stat; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "error: required command unavailable: ${command_name}" >&2
    exit 2
  }
done

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "error: GITHUB_TOKEN is required to download the proven Actions artifact" >&2
  exit 2
fi

outer_zip="${workdir}/proven-runtime-app-artifact.zip"
artifact_url="https://api.github.com/repos/arjunkl/SelacoiOS/actions/artifacts/${artifact_id}/zip"
curl --fail --location --silent --show-error \
  -H "Authorization: Bearer ${GITHUB_TOKEN}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "${artifact_url}" -o "${outer_zip}"

outer_sha256="$(shasum -a 256 "${outer_zip}" | awk '{print $1}')"
if [[ "${outer_sha256}" != "${expected_outer_sha256}" ]]; then
  echo "error: downloaded source artifact digest mismatch: ${outer_sha256}" >&2
  exit 1
fi
unzip -q "${outer_zip}" -d "${workdir}/outer"

inner_zip="${workdir}/outer/Selaco-runtime-bootstrap-unsigned-app.zip"
if [[ ! -f "${inner_zip}" ]]; then
  echo "error: proven Actions artifact lacks the expected inner app archive" >&2
  exit 1
fi
inner_sha256="$(shasum -a 256 "${inner_zip}" | awk '{print $1}')"
if [[ "${inner_sha256}" != "${expected_inner_sha256}" ]]; then
  echo "error: proven inner app archive digest mismatch: ${inner_sha256}" >&2
  exit 1
fi
unzip -q "${inner_zip}" -d "${workdir}/inner"

source_app="${workdir}/inner/Selaco-runtime-bootstrap-unsigned.app"
if [[ ! -d "${source_app}" || ! -f "${source_app}/Selaco" || ! -f "${source_app}/Info.plist" ]]; then
  echo "error: proven runtime app bundle is incomplete" >&2
  exit 1
fi

packaged_app="${workdir}/stage/Payload/Selaco.app"
cp -R "${source_app}" "${packaged_app}"

python3 - "${packaged_app}/Info.plist" <<'PY'
from __future__ import annotations

import pathlib
import plistlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open("rb") as stream:
    plist = plistlib.load(stream)

plist.update(
    {
        "CFBundleIdentifier": "am.arjunkl.selacoios.runtime.m1",
        "CFBundleName": "SelacoiOS Runtime",
        "CFBundleDisplayName": "SelacoiOS Runtime",
        "CFBundleShortVersionString": "0.1",
        "CFBundleVersion": "1",
        "UISupportedInterfaceOrientations": [
            "UIInterfaceOrientationLandscapeLeft",
            "UIInterfaceOrientationLandscapeRight",
        ],
        "UILaunchScreen": {},
        "UIFileSharingEnabled": True,
        "LSSupportsOpeningDocumentsInPlace": True,
    }
)

with path.open("wb") as stream:
    plistlib.dump(plist, stream, fmt=plistlib.FMT_BINARY, sort_keys=True)
PY

python3 - "${packaged_app}/Info.plist" <<'PY'
from __future__ import annotations

import pathlib
import plistlib
import sys

path = pathlib.Path(sys.argv[1])
with path.open("rb") as stream:
    plist = plistlib.load(stream)

expected = {
    "CFBundleIdentifier": "am.arjunkl.selacoios.runtime.m1",
    "CFBundleExecutable": "Selaco",
    "CFBundlePackageType": "APPL",
    "MinimumOSVersion": "15.0",
}
for key, value in expected.items():
    if plist.get(key) != value:
        raise SystemExit(f"invalid {key}: {plist.get(key)!r}")
if plist.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
    raise SystemExit("runtime app is not an iPhoneOS bundle")
if plist.get("UIRequiredDeviceCapabilities") != ["arm64"]:
    raise SystemExit("runtime app lacks the arm64 device requirement")
PY

file "${packaged_app}/Selaco" | tee "${evidence_dir}/executable-file.txt"
xcrun lipo -info "${packaged_app}/Selaco" | tee "${evidence_dir}/architecture.txt"
xcrun vtool -show-build "${packaged_app}/Selaco" | tee "${evidence_dir}/build-version.txt"
if ! grep -q 'arm64' "${evidence_dir}/architecture.txt"; then
  echo "error: runtime executable is not arm64" >&2
  exit 1
fi
if ! grep -q 'platform IOS' "${evidence_dir}/build-version.txt"; then
  echo "error: runtime executable is not marked for iOS" >&2
  exit 1
fi
if codesign -d --verbose=2 "${packaged_app}" >"${evidence_dir}/codesign.txt" 2>&1; then
  echo "error: source app was unexpectedly signed" >&2
  exit 1
fi
echo "unsigned=yes" >> "${evidence_dir}/codesign.txt"

runtime_ipa="${output_dir}/Selaco-runtime-bootstrap-unsigned.ipa"
(
  cd "${workdir}/stage"
  ditto -c -k --sequesterRsrc Payload "${runtime_ipa}"
)

unzip -Z1 "${runtime_ipa}" > "${evidence_dir}/ipa-contents.txt"
if ! grep -Fxq 'Payload/Selaco.app/Selaco' "${evidence_dir}/ipa-contents.txt"; then
  echo "error: IPA lacks Payload/Selaco.app/Selaco" >&2
  exit 1
fi
if grep -Eiq '\.(mobileprovision|p12)$' "${evidence_dir}/ipa-contents.txt"; then
  echo "error: IPA unexpectedly contains signing material" >&2
  exit 1
fi

ipa_sha256="$(shasum -a 256 "${runtime_ipa}" | awk '{print $1}')"
ipa_size="$(stat -f '%z' "${runtime_ipa}")"
printf '%s  %s\n' "${ipa_sha256}" "$(basename "${runtime_ipa}")" | tee "${evidence_dir}/ipa-sha256.txt"
echo "ipa_size=${ipa_size}" | tee "${evidence_dir}/ipa-size.txt"
cat > "${evidence_dir}/manifest.txt" <<MANIFEST
source_artifact_id=${artifact_id}
source_artifact_sha256=${outer_sha256}
source_inner_archive_sha256=${inner_sha256}
bundle_identifier=am.arjunkl.selacoios.runtime.m1
platform=iphoneos
architecture=arm64
minimum_os=15.0
unsigned=yes
artifact=Selaco-runtime-bootstrap-unsigned.ipa
artifact_sha256=${ipa_sha256}
artifact_size=${ipa_size}
physical_execution=not_tested
purpose=UIKit plus MoltenVK instance Metal-surface and graphics-present queue diagnostic
MANIFEST
printf 'PASS\n' > "${evidence_dir}/result.txt"
echo "runtime-ipa-repack: PASS"
