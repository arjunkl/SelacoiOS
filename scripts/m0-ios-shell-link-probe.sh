#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"

evidence_dir="${repo_root}/build/evidence/m0-ios-shell"
artifact_dir="${repo_root}/build/artifacts/m0-ios-shell"
rm -rf "${evidence_dir}" "${artifact_dir}"
mkdir -p "${evidence_dir}" "${artifact_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "ios-shell-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: the iPhoneOS shell probe must run on macOS with Xcode" >&2
  exit 2
fi

for command_name in git cmake xcrun xcodebuild file nm otool plutil shasum strings ditto; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

for required_var in GZSELACO_REPOSITORY GZSELACO_COMMIT; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "error: ${required_var} is missing from SOURCE_PIN.env" >&2
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
build_dir="${workdir}/ios-shell-build"

echo "== Fetch pinned source =="
git init -q "${source_dir}"
git -C "${source_dir}" remote add origin "${GZSELACO_REPOSITORY}"
git -C "${source_dir}" fetch -q --depth=1 origin "${GZSELACO_COMMIT}"
git -C "${source_dir}" checkout -q --detach FETCH_HEAD
resolved_commit="$(git -C "${source_dir}" rev-parse HEAD)"
if [[ "${resolved_commit}" != "${GZSELACO_COMMIT}" ]]; then
  echo "error: source pin resolved to ${resolved_commit}, expected ${GZSELACO_COMMIT}" >&2
  exit 1
fi
echo "source: ${resolved_commit}"

echo "== Configure unsigned arm64 iPhoneOS application shell =="
cmake \
  -G Xcode \
  -S "${repo_root}/platform/ios-shell" \
  -B "${build_dir}" \
  -DGZSELACO_SOURCE_DIR="${source_dir}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "${evidence_dir}/configure.log"

cp "${build_dir}/CMakeCache.txt" "${evidence_dir}/CMakeCache.txt"

xcode_project="$(find "${build_dir}" -maxdepth 1 -type d -name '*.xcodeproj' -print -quit)"
if [[ -z "${xcode_project}" ]]; then
  echo "error: CMake did not produce an Xcode project" >&2
  exit 1
fi
xcodebuild -project "${xcode_project}" -target SelacoiOSShell -configuration Release -sdk iphoneos -showBuildSettings \
  > "${evidence_dir}/build-settings.txt"

echo "== Build unsigned arm64 iPhoneOS application shell =="
cmake --build "${build_dir}" \
  --config Release \
  --target selaco-ios-shell-boundary \
  --parallel 2 \
  2>&1 | tee "${evidence_dir}/build.log"

app_path="$(find "${build_dir}" -type d -name 'SelacoiOSShell.app' -print -quit)"
if [[ -z "${app_path}" || ! -d "${app_path}" ]]; then
  echo "error: expected SelacoiOSShell.app was not produced" >&2
  exit 1
fi

executable_path="${app_path}/SelacoiOSShell"
info_plist_path="${app_path}/Info.plist"
if [[ ! -f "${executable_path}" || ! -f "${info_plist_path}" ]]; then
  echo "error: app bundle is missing its executable or Info.plist" >&2
  exit 1
fi

echo "== Validate bundle and Mach-O boundary =="
plutil -lint "${info_plist_path}" | tee "${evidence_dir}/plist-lint.txt"
plutil -p "${info_plist_path}" | tee "${evidence_dir}/plist.txt"

bundle_identifier="$(plutil -extract CFBundleIdentifier raw "${info_plist_path}")"
minimum_os="$(plutil -extract MinimumOSVersion raw "${info_plist_path}")"
if [[ "${bundle_identifier}" != "am.arjunkl.selacoios.m0shell" ]]; then
  echo "error: unexpected bundle identifier: ${bundle_identifier}" >&2
  exit 1
fi
if [[ "${minimum_os}" != "15.0" ]]; then
  echo "error: unexpected deployment target: ${minimum_os}" >&2
  exit 1
fi

file "${executable_path}" | tee "${evidence_dir}/executable-file.txt"
xcrun lipo -info "${executable_path}" | tee "${evidence_dir}/executable-architecture.txt"
xcrun vtool -show-build "${executable_path}" | tee "${evidence_dir}/mach-build-version.txt"
otool -L "${executable_path}" | tee "${evidence_dir}/linked-libraries.txt"
nm -gU "${executable_path}" | tee "${evidence_dir}/global-symbols.txt"

architecture_info="$(cat "${evidence_dir}/executable-architecture.txt")"
if [[ "${architecture_info}" != *"arm64"* || "${architecture_info}" == *"x86_64"* ]]; then
  echo "error: executable is not a physical-device-only arm64 Mach-O" >&2
  exit 1
fi
if ! grep -q 'platform IOS' "${evidence_dir}/mach-build-version.txt"; then
  echo "error: Mach-O build metadata does not identify the iOS platform" >&2
  exit 1
fi

for framework in UIKit CoreGraphics Metal MetalKit QuartzCore Foundation; do
  if ! grep -q "/${framework}\.framework/${framework}" "${evidence_dir}/linked-libraries.txt"; then
    echo "error: expected ${framework} framework linkage is absent" >&2
    exit 1
  fi
done

for symbol in _SelacoIOSGameSignature _SelacoIOSEngineVersion _SelacoIOSEngineSelfTest; do
  if ! grep -q "${symbol}" "${evidence_dir}/global-symbols.txt"; then
    echo "error: pinned-engine bridge symbol is absent: ${symbol}" >&2
    exit 1
  fi
done

if ! strings "${executable_path}" | grep -q '^SELACO$'; then
  echo "error: pinned GZSelaco game signature is absent from the executable" >&2
  exit 1
fi
if ! strings "${executable_path}" | grep -q 'GZDoom 4\.13\.0'; then
  echo "error: pinned GZSelaco engine version is absent from the executable" >&2
  exit 1
fi

if [[ -d "${app_path}/_CodeSignature" ]]; then
  echo "error: Milestone 0 shell unexpectedly contains a code signature" >&2
  exit 1
fi

shasum -a 256 "${executable_path}" | tee "${evidence_dir}/executable-sha256.txt"
ditto -c -k --sequesterRsrc --keepParent "${app_path}" "${artifact_dir}/SelacoiOSShell-unsigned-app.zip"
shasum -a 256 "${artifact_dir}/SelacoiOSShell-unsigned-app.zip" | tee "${evidence_dir}/app-zip-sha256.txt"

cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
source_repository=${GZSELACO_REPOSITORY}
source_commit=${resolved_commit}
host_os=$(sw_vers -productVersion)
xcode=$(xcodebuild -version | tr '\n' ' ')
iphoneos_sdk=${iphoneos_sdk_version}
deployment_target=${minimum_os}
architecture=arm64
generator=Xcode
bundle_identifier=${bundle_identifier}
app=${app_path}
executable=${executable_path}
signed=no
renderer_surface=MetalKit
engine_bridge=GZSelaco_SuperFastHashI
engine_runtime=not_started
moltenvk=not_integrated
sdl=not_integrated
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "ios-shell-probe: PASS"
