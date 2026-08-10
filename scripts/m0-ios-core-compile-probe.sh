#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"

evidence_dir="${repo_root}/build/evidence/m0-ios-core"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "ios-core-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: the iPhoneOS compile probe must run on macOS with Xcode" >&2
  exit 2
fi

for command_name in git cmake xcrun xcodebuild file ar shasum; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

echo "== Host and SDK environment =="
sw_vers
xcodebuild -version
cmake --version | head -n 1
iphoneos_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
iphoneos_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iphoneos SDK path: ${iphoneos_sdk_path}"
echo "iphoneos SDK version: ${iphoneos_sdk_version}"
xcrun --sdk iphoneos --find clang

source_dir="${workdir}/GZSelaco"
build_dir="${workdir}/ios-core-build"

echo "== Fetch pinned source =="
git init -q "${source_dir}"
git -C "${source_dir}" remote add origin "${GZSELACO_REPOSITORY}"
git -C "${source_dir}" fetch -q --depth=1 origin "${GZSELACO_COMMIT}"
git -C "${source_dir}" checkout -q --detach FETCH_HEAD
resolved_commit="$(git -C "${source_dir}" rev-parse HEAD)"
[[ "${resolved_commit}" == "${GZSELACO_COMMIT}" ]]
echo "source: ${resolved_commit}"

echo "== Configure arm64 iPhoneOS static-library boundary =="
cmake \
  -G Xcode \
  -S "${repo_root}/cmake/ios-core-probe" \
  -B "${build_dir}" \
  -DGZSELACO_SOURCE_DIR="${source_dir}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "${evidence_dir}/configure.log"

cp "${build_dir}/CMakeCache.txt" "${evidence_dir}/CMakeCache.txt"

echo "== Build arm64 iPhoneOS core boundary =="
cmake --build "${build_dir}" \
  --config Release \
  --target selaco-ios-core-boundary \
  --parallel 2 \
  2>&1 | tee "${evidence_dir}/build.log"

archive_path="$(find "${build_dir}" -type f -name 'libgzselaco-ios-core-probe.a' -print -quit)"
if [[ -z "${archive_path}" || ! -f "${archive_path}" ]]; then
  echo "error: expected GZSelaco iOS core archive was not produced" >&2
  exit 1
fi

archive_file_info="$(file "${archive_path}")"
archive_lipo_info="$(xcrun lipo -info "${archive_path}")"
echo "${archive_file_info}" | tee "${evidence_dir}/archive-file.txt"
echo "${archive_lipo_info}" | tee "${evidence_dir}/archive-architecture.txt"

if [[ "${archive_lipo_info}" != *"arm64"* ]]; then
  echo "error: archive does not report arm64 architecture" >&2
  exit 1
fi
if [[ "${archive_lipo_info}" == *"x86_64"* ]]; then
  echo "error: physical-device archive unexpectedly contains x86_64" >&2
  exit 1
fi

ar -t "${archive_path}" | tee "${evidence_dir}/archive-members.txt"
shasum -a 256 "${archive_path}" | tee "${evidence_dir}/archive-sha256.txt"

cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
source_repository=${GZSELACO_REPOSITORY}
source_commit=${resolved_commit}
host_os=$(sw_vers -productVersion)
xcode=$(xcodebuild -version | tr '\n' ' ')
iphoneos_sdk=${iphoneos_sdk_version}
deployment_target=15.0
architecture=arm64
generator=Xcode
archive=${archive_path}
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "ios-core-probe: PASS"
