#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/MOLTENVK_PIN.env"

evidence_dir="${repo_root}/build/evidence/m0-moltenvk-package"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "moltenvk-package-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

for command_name in curl python3 tar shasum file xcrun; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

for required_var in MOLTENVK_REPOSITORY MOLTENVK_TAG MOLTENVK_ASSET_NAME MOLTENVK_ASSET_SHA256; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "error: ${required_var} is missing from MOLTENVK_PIN.env" >&2
    exit 2
  fi
done

release_json="${evidence_dir}/release.json"
asset_metadata="${evidence_dir}/asset-metadata.txt"
asset_tar="${workdir}/${MOLTENVK_ASSET_NAME}"
extract_dir="${workdir}/package"
mkdir -p "${extract_dir}"

api_url="https://api.github.com/repos/${MOLTENVK_REPOSITORY}/releases/tags/${MOLTENVK_TAG}"
header_args=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  header_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

echo "== Resolve official release asset =="
curl --fail --silent --show-error --location --retry 3 \
  "${header_args[@]}" \
  "${api_url}" \
  --output "${release_json}"

python3 - "${release_json}" "${MOLTENVK_TAG}" "${MOLTENVK_ASSET_NAME}" "${asset_metadata}" <<'PY'
import json
import pathlib
import sys

release_path, expected_tag, expected_asset, output_path = sys.argv[1:]
release = json.loads(pathlib.Path(release_path).read_text(encoding="utf-8"))
if release.get("tag_name") != expected_tag:
    raise SystemExit(f"release tag mismatch: {release.get('tag_name')!r} != {expected_tag!r}")
assets = release.get("assets") or []
for asset in assets:
    print(f"asset: {asset.get('name')} size={asset.get('size')} digest={asset.get('digest')}")
selected = next((asset for asset in assets if asset.get("name") == expected_asset), None)
if selected is None:
    names = ", ".join(str(asset.get("name")) for asset in assets)
    raise SystemExit(f"release asset {expected_asset!r} not found; available: {names}")
fields = {
    "release_id": release.get("id"),
    "release_tag": release.get("tag_name"),
    "release_target_commitish": release.get("target_commitish"),
    "release_published_at": release.get("published_at"),
    "asset_id": selected.get("id"),
    "asset_name": selected.get("name"),
    "asset_size": selected.get("size"),
    "asset_digest": selected.get("digest") or "",
    "asset_url": selected.get("browser_download_url"),
}
pathlib.Path(output_path).write_text(
    "".join(f"{key}={value}\n" for key, value in fields.items()),
    encoding="utf-8",
)
PY

cat "${asset_metadata}"
asset_url="$(sed -n 's/^asset_url=//p' "${asset_metadata}")"
api_digest="$(sed -n 's/^asset_digest=sha256://p' "${asset_metadata}")"
if [[ -z "${asset_url}" ]]; then
  echo "error: release metadata did not contain a browser download URL" >&2
  exit 1
fi

curl --fail --silent --show-error --location --retry 3 \
  "${asset_url}" \
  --output "${asset_tar}"

asset_sha256="$(shasum -a 256 "${asset_tar}" | awk '{print $1}')"
asset_size="$(stat -f '%z' "${asset_tar}")"
printf '%s  %s\n' "${asset_sha256}" "${MOLTENVK_ASSET_NAME}" | tee "${evidence_dir}/asset-sha256.txt"
echo "asset_size_downloaded=${asset_size}" | tee "${evidence_dir}/asset-size.txt"

if [[ -n "${api_digest}" && "${asset_sha256}" != "${api_digest}" ]]; then
  echo "error: downloaded asset hash ${asset_sha256} differs from GitHub release digest ${api_digest}" >&2
  exit 1
fi
if [[ "${asset_sha256}" != "${MOLTENVK_ASSET_SHA256}" ]]; then
  echo "error: downloaded asset hash ${asset_sha256} differs from committed pin ${MOLTENVK_ASSET_SHA256}" >&2
  exit 1
fi

echo "== Extract and inspect iPhoneOS static-library slice =="
tar -xf "${asset_tar}" -C "${extract_dir}"
find "${extract_dir}" -maxdepth 8 -print | sed "s#${extract_dir}#.#" | sort > "${evidence_dir}/package-tree.txt"

xcframework_path="$(find "${extract_dir}" -type d -name 'MoltenVK.xcframework' -path '*/static/*' -print -quit)"
if [[ -z "${xcframework_path}" || ! -d "${xcframework_path}" ]]; then
  echo "error: static MoltenVK.xcframework is absent from the release package" >&2
  exit 1
fi

library_path="$(find "${xcframework_path}" -type f -name 'libMoltenVK.a' -path '*ios-arm64*' ! -path '*simulator*' -print -quit)"
include_dir="$(find "${extract_dir}" -type d -path '*/MoltenVK/include' -print -quit)"
vulkan_header="${include_dir}/vulkan/vulkan.h"
if [[ -z "${library_path}" || ! -f "${library_path}" ]]; then
  echo "error: physical-device ios-arm64 libMoltenVK.a slice is absent" >&2
  exit 1
fi
if [[ -z "${include_dir}" || ! -f "${vulkan_header}" ]]; then
  echo "error: release package has no shared vulkan/vulkan.h header" >&2
  exit 1
fi

file "${library_path}" | tee "${evidence_dir}/library-file.txt"
xcrun lipo -info "${library_path}" | tee "${evidence_dir}/library-architecture.txt"
architecture_info="$(cat "${evidence_dir}/library-architecture.txt")"
if [[ "${architecture_info}" != *"arm64"* || "${architecture_info}" == *"x86_64"* ]]; then
  echo "error: selected MoltenVK library is not a physical-device arm64 binary" >&2
  exit 1
fi

xcframework_rel="${xcframework_path#${extract_dir}/}"
library_rel="${library_path#${extract_dir}/}"
include_rel="${include_dir#${extract_dir}/}"
vulkan_header_rel="${vulkan_header#${extract_dir}/}"
cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
repository=${MOLTENVK_REPOSITORY}
tag=${MOLTENVK_TAG}
asset=${MOLTENVK_ASSET_NAME}
asset_sha256=${asset_sha256}
api_digest=${api_digest}
xcframework_path=${xcframework_rel}
library_path=${library_rel}
include_dir=${include_rel}
vulkan_header=${vulkan_header_rel}
architecture=arm64
platform=iphoneos
linkage=static
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "moltenvk-package-probe: PASS"
