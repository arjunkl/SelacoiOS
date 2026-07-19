#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"

evidence_dir="${repo_root}/build/evidence/m0-full-engine-app"
artifact_dir="${repo_root}/build/artifacts/m0-full-engine-app"
tmp_root="${repo_root}/build/work/m0-full-engine-app"
real_rm="$(command -v rm)"

"${real_rm}" -rf "${evidence_dir}" "${artifact_dir}" "${tmp_root}"
mkdir -p "${evidence_dir}" "${artifact_dir}" "${tmp_root}/bin" "${tmp_root}/tmp"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

cleanup() {
  "${real_rm}" -rf "${tmp_root}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "full-engine-app-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: full-engine app artifact validation requires macOS and Xcode" >&2
  exit 2
fi

for command_name in bash python3 xcrun file otool nm plutil codesign ditto shasum; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

compile_probe="${repo_root}/scripts/m0-full-engine-compile-probe.sh"
if [[ ! -f "${compile_probe}" ]]; then
  echo "error: full-engine compile probe is missing" >&2
  exit 2
fi

# Preserve only the top-level mktemp workspaces created beneath the controlled
# temporary root. All ordinary rm calls inside dependency builds still delegate
# to the system utility.
cat > "${tmp_root}/bin/rm" <<'SHIM'
#!/usr/bin/env bash
set -euo pipefail
real_rm="${SELACOIOS_REAL_RM:?}"
preserve_root="${SELACOIOS_PRESERVE_TMP_ROOT:?}"
last="${!#:-}"
if [[ "$#" -ge 1 && "${last}" == "${preserve_root}"/tmp.* && "$(dirname "${last}")" == "${preserve_root}" ]]; then
  echo "SelacoiOS: preserving compile workspace ${last}"
  exit 0
fi
exec "${real_rm}" "$@"
SHIM
chmod +x "${tmp_root}/bin/rm"

export SELACOIOS_REAL_RM="${real_rm}"
export SELACOIOS_PRESERVE_TMP_ROOT="${tmp_root}/tmp"
export TMPDIR="${tmp_root}/tmp"
export PATH="${tmp_root}/bin:${PATH}"

printf '== Reproduce complete full-engine build ==\n'
bash "${compile_probe}"

compile_outcome="$(sed -n 's/^outcome=//p' "${repo_root}/build/evidence/m0-full-engine-compile/outcome.txt")"
if [[ "${compile_outcome}" != "FULL_COMPILE_PASS" ]]; then
  echo "error: app extraction requires FULL_COMPILE_PASS, got ${compile_outcome:-missing}" >&2
  exit 1
fi

app_bundle="$(find "${tmp_root}/tmp" -type d -path '*/engine-build/Release/Selaco.app' -print -quit)"
if [[ -z "${app_bundle}" || ! -d "${app_bundle}" ]]; then
  echo "error: successful compile did not leave a Selaco.app bundle" >&2
  exit 1
fi

info_plist="${app_bundle}/Info.plist"
executable="${app_bundle}/Selaco"
if [[ ! -f "${info_plist}" || ! -f "${executable}" ]]; then
  echo "error: Selaco.app lacks Info.plist or its executable" >&2
  exit 1
fi

printf '== Validate full-engine app bundle ==\n'
plutil -lint "${info_plist}" | tee "${evidence_dir}/plist-lint.txt"
plutil -p "${info_plist}" > "${evidence_dir}/Info.plist.txt"
file "${executable}" | tee "${evidence_dir}/executable-file.txt"
xcrun lipo -info "${executable}" | tee "${evidence_dir}/executable-architecture.txt"
xcrun vtool -show-build "${executable}" | tee "${evidence_dir}/executable-build-version.txt"
otool -L "${executable}" | tee "${evidence_dir}/executable-linked-libraries.txt"
nm -g "${executable}" > "${evidence_dir}/executable-global-symbols.txt"

architecture_info="$(cat "${evidence_dir}/executable-architecture.txt")"
if [[ "${architecture_info}" != *"arm64"* || "${architecture_info}" == *"x86_64"* ]]; then
  echo "error: full-engine executable is not physical-device-only arm64" >&2
  exit 1
fi
if ! grep -q 'platform IOS' "${evidence_dir}/executable-build-version.txt"; then
  echo "error: full-engine executable is not marked for iOS" >&2
  exit 1
fi
if ! grep -Eq 'minos 15(\.0+)?$|minos 15(\.0+)?[[:space:]]' "${evidence_dir}/executable-build-version.txt"; then
  echo "error: expected iOS 15.0 deployment target is absent" >&2
  exit 1
fi

python3 - "${evidence_dir}/executable-linked-libraries.txt" <<'PY'
from __future__ import annotations

import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()[1:]
unexpected: list[str] = []
for raw in lines:
    dependency = raw.strip().split(" (compatibility", 1)[0]
    if not dependency:
        continue
    if dependency.startswith(("/System/Library/", "/usr/lib/")):
        continue
    unexpected.append(dependency)
if unexpected:
    raise SystemExit("unexpected non-system dynamic dependencies: " + ", ".join(unexpected))
PY

codesign_status=0
codesign -d --verbose=4 "${app_bundle}" > "${evidence_dir}/codesign.txt" 2>&1 || codesign_status=$?
if [[ "${codesign_status}" == "0" ]]; then
  echo "error: full-engine app was unexpectedly signed" >&2
  exit 1
fi
echo "unsigned=yes" | tee -a "${evidence_dir}/codesign.txt"

for retained_symbol in _main _Args _Video _PerfToSec; do
  if ! grep -q "${retained_symbol}" "${evidence_dir}/executable-global-symbols.txt"; then
    echo "error: executable lacks retained iOS runtime symbol ${retained_symbol}" >&2
    exit 1
  fi
done

preserved_app="${artifact_dir}/Selaco-full-engine-unsigned.app"
cp -R "${app_bundle}" "${preserved_app}"
artifact_zip="${artifact_dir}/Selaco-full-engine-unsigned-app.zip"
ditto -c -k --sequesterRsrc --keepParent "${preserved_app}" "${artifact_zip}"
artifact_sha256="$(shasum -a 256 "${artifact_zip}" | awk '{print $1}')"
artifact_size="$(stat -f '%z' "${artifact_zip}")"
printf '%s  %s\n' "${artifact_sha256}" "$(basename "${artifact_zip}")" | tee "${evidence_dir}/artifact-sha256.txt"
echo "artifact_size=${artifact_size}" | tee "${evidence_dir}/artifact-size.txt"

cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
engine_repository=${GZSELACO_REPOSITORY}
engine_commit=${GZSELACO_COMMIT}
platform=iphoneos
architecture=arm64
deployment_target=15.0
configuration=Release
renderer=vulkan_only
bundle=Selaco.app
executable=Selaco
compile=passed
link=passed
bundle_validation=passed
unsigned=yes
artifact=Selaco-full-engine-unsigned-app.zip
artifact_sha256=${artifact_sha256}
artifact_size=${artifact_size}
physical_execution=not_tested
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "full-engine-app-probe: PASS"
