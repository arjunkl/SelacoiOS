#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/MOLTENVK_PIN.env"

evidence_dir="${repo_root}/build/evidence/m1-moltenvk-dynamic-package"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() { rm -rf "${workdir}"; }
trap cleanup EXIT

asset="${workdir}/${MOLTENVK_ASSET_NAME}"
extract="${workdir}/extract"
mkdir -p "${extract}"
url="https://github.com/${MOLTENVK_REPOSITORY}/releases/download/${MOLTENVK_TAG}/${MOLTENVK_ASSET_NAME}"
curl --fail --silent --show-error --location --retry 3 "${url}" -o "${asset}"
actual_sha256="$(shasum -a 256 "${asset}" | awk '{print $1}')"
[[ "${actual_sha256}" == "${MOLTENVK_ASSET_SHA256}" ]]
tar -xf "${asset}" -C "${extract}"
find "${extract}" -maxdepth 8 -print | sort > "${evidence_dir}/package-tree.txt"

framework="$(find "${extract}" -type d -name 'MoltenVK.framework' -path '*dynamic*' -path '*ios-arm64*' ! -path '*simulator*' -print -quit)"
if [[ -z "${framework}" || ! -d "${framework}" || ! -f "${framework}/MoltenVK" ]]; then
  echo "error: pinned package lacks a dynamic arm64 iPhoneOS MoltenVK.framework" >&2
  exit 1
fi

file "${framework}/MoltenVK" | tee "${evidence_dir}/framework-file.txt"
xcrun lipo -info "${framework}/MoltenVK" | tee "${evidence_dir}/framework-architecture.txt"
xcrun vtool -show-build "${framework}/MoltenVK" | tee "${evidence_dir}/framework-build-version.txt"
otool -D "${framework}/MoltenVK" | tee "${evidence_dir}/framework-install-name.txt"
nm -gU "${framework}/MoltenVK" | grep -E ' _vkGetInstanceProcAddr$' | tee "${evidence_dir}/vk-get-instance-proc-addr.txt"

if ! grep -q 'arm64' "${evidence_dir}/framework-architecture.txt"; then
  echo "error: dynamic MoltenVK framework is not arm64" >&2
  exit 1
fi
if ! grep -q 'platform IOS' "${evidence_dir}/framework-build-version.txt"; then
  echo "error: dynamic MoltenVK framework is not iPhoneOS" >&2
  exit 1
fi
if [[ ! -s "${evidence_dir}/vk-get-instance-proc-addr.txt" ]]; then
  echo "error: dynamic MoltenVK framework does not export vkGetInstanceProcAddr" >&2
  exit 1
fi

relative_framework="${framework#${extract}/}"
cat > "${evidence_dir}/manifest.txt" <<MANIFEST
moltenvk_tag=${MOLTENVK_TAG}
asset_sha256=${actual_sha256}
dynamic_framework_relative_path=${relative_framework}
architecture=arm64
platform=iphoneos
vk_get_instance_proc_addr=exported
result=PASS
MANIFEST
printf 'PASS\n' > "${evidence_dir}/result.txt"
echo "moltenvk-dynamic-package-probe: PASS (${relative_framework})"
