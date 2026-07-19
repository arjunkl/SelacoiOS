#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/DEPENDENCY_TRIAL_PINS.env"

evidence_dir="${repo_root}/build/evidence/m0-zmusic-ios"
artifact_dir="${repo_root}/build/artifacts/m0-zmusic-ios"
artifact_zip="${repo_root}/build/artifacts/zmusic-ios-arm64-probe.zip"
rm -rf "${evidence_dir}" "${artifact_dir}" "${artifact_zip}"
mkdir -p "${evidence_dir}" "${artifact_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "zmusic-ios-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: ZMusic iPhoneOS probe requires macOS and Xcode" >&2
  exit 2
fi

for command_name in git cmake xcrun xcodebuild file nm shasum ditto python3; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

for required_var in ZMUSIC_REPOSITORY ZMUSIC_COMMIT ZMUSIC_PROJECT_VERSION; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "error: ${required_var} is missing from DEPENDENCY_TRIAL_PINS.env" >&2
    exit 2
  fi
done

source_dir="${workdir}/ZMusic"
build_dir="${workdir}/build"
patcher="${repo_root}/scripts/patch-zmusic-ios-m0.py"
contract_source="${repo_root}/probes/zmusic-api-contract.cpp"
contract_object="${artifact_dir}/zmusic-api-contract.o"

if [[ ! -f "${patcher}" || ! -f "${contract_source}" ]]; then
  echo "error: committed ZMusic patcher or API contract is missing" >&2
  exit 2
fi

echo "== Host and SDK environment =="
sw_vers
xcodebuild -version
cmake --version | head -n 1
iphoneos_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
iphoneos_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iphoneos SDK path: ${iphoneos_sdk_path}"
echo "iphoneos SDK version: ${iphoneos_sdk_version}"

echo "== Fetch exact ZMusic compatibility trial =="
git init -q "${source_dir}"
git -C "${source_dir}" remote add origin "${ZMUSIC_REPOSITORY}"
git -C "${source_dir}" fetch -q --depth=1 origin "${ZMUSIC_COMMIT}"
git -C "${source_dir}" checkout -q --detach FETCH_HEAD
resolved_commit="$(git -C "${source_dir}" rev-parse HEAD)"
if [[ "${resolved_commit}" != "${ZMUSIC_COMMIT}" ]]; then
  echo "error: ZMusic resolved to ${resolved_commit}, expected ${ZMUSIC_COMMIT}" >&2
  exit 1
fi

python3 "${patcher}" "${source_dir}"
git -C "${source_dir}" diff --check
git -C "${source_dir}" diff --binary > "${evidence_dir}/applied-zmusic-ios.patch"
patcher_sha256="$(shasum -a 256 "${patcher}" | awk '{print $1}')"
echo "patcher_sha256=${patcher_sha256}" | tee "${evidence_dir}/patcher-sha256.txt"

if ! grep -Fq "VERSION ${ZMUSIC_PROJECT_VERSION}" "${source_dir}/CMakeLists.txt"; then
  echo "error: pinned ZMusic source does not declare expected project version ${ZMUSIC_PROJECT_VERSION}" >&2
  exit 1
fi
if ! grep -Fq 'option(ZMUSIC_ENABLE_FLUIDSYNTH' "${source_dir}/thirdparty/CMakeLists.txt"; then
  echo "error: deterministic iOS patch did not add the FluidSynth policy switch" >&2
  exit 1
fi

echo "== Configure static ZMusic for arm64 iPhoneOS =="
cmake \
  -G Xcode \
  -S "${source_dir}" \
  -B "${build_dir}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DBUILD_SHARED_LIBS=OFF \
  -DZMUSIC_INSTALL=OFF \
  -DZMUSIC_ENABLE_FLUIDSYNTH=OFF \
  -DDYN_SNDFILE=OFF \
  -DDYN_MPG123=OFF \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "${evidence_dir}/configure.log"

cp "${build_dir}/CMakeCache.txt" "${evidence_dir}/CMakeCache.txt"
xcode_project="$(find "${build_dir}" -maxdepth 1 -type d -name '*.xcodeproj' -print -quit)"
if [[ -z "${xcode_project}" ]]; then
  echo "error: ZMusic configure did not produce an Xcode project" >&2
  exit 1
fi
xcodebuild -project "${xcode_project}" -target zmusic -configuration Release -sdk iphoneos -showBuildSettings \
  > "${evidence_dir}/build-settings.txt"

echo "== Build static ZMusic target without FluidSynth =="
cmake --build "${build_dir}" \
  --config Release \
  --target zmusic \
  --parallel 3 \
  2>&1 | tee "${evidence_dir}/build.log"

zmusic_library="$(find "${build_dir}" -type f -name 'libzmusic.a' -print -quit)"
if [[ -z "${zmusic_library}" || ! -f "${zmusic_library}" ]]; then
  echo "error: static libzmusic.a was not produced" >&2
  exit 1
fi

file "${zmusic_library}" | tee "${evidence_dir}/library-file.txt"
xcrun lipo -info "${zmusic_library}" | tee "${evidence_dir}/library-architecture.txt"
library_architecture="$(cat "${evidence_dir}/library-architecture.txt")"
if [[ "${library_architecture}" != *"arm64"* || "${library_architecture}" == *"x86_64"* ]]; then
  echo "error: libzmusic.a is not physical-device-only arm64" >&2
  exit 1
fi

nm -g "${zmusic_library}" > "${evidence_dir}/library-global-symbols.txt"
for symbol in \
    _ZMusic_SetCallbacks _ZMusic_SetGenMidi _ZMusic_SetWgOpn _ZMusic_SetDmxGus \
    _ZMusic_IdentifyMIDIType _ZMusic_CreateMIDISource _ZMusic_OpenSongMem \
    _ZMusic_VolumeChanged _ZMusic_GetStats _ZMusic_Close; do
  if ! grep -q "${symbol}" "${evidence_dir}/library-global-symbols.txt"; then
    echo "error: expected GZSelaco-facing ZMusic symbol is absent: ${symbol}" >&2
    exit 1
  fi
done

echo "== Compile GZSelaco-facing ZMusic API contract =="
xcrun --sdk iphoneos clang++ \
  -std=c++17 \
  -arch arm64 \
  -isysroot "${iphoneos_sdk_path}" \
  -miphoneos-version-min=15.0 \
  -DZMUSIC_STATIC=1 \
  -I "${source_dir}/include" \
  -Wall -Wextra -Werror \
  -c "${contract_source}" \
  -o "${contract_object}" \
  2>&1 | tee "${evidence_dir}/api-contract-compile.log"

file "${contract_object}" | tee "${evidence_dir}/api-contract-file.txt"
xcrun lipo -info "${contract_object}" | tee "${evidence_dir}/api-contract-architecture.txt"

cp "${zmusic_library}" "${artifact_dir}/libzmusic-ios-arm64.a"
shasum -a 256 "${artifact_dir}/libzmusic-ios-arm64.a" | tee "${evidence_dir}/library-sha256.txt"
shasum -a 256 "${contract_object}" | tee "${evidence_dir}/api-contract-sha256.txt"

ditto -c -k --sequesterRsrc --keepParent \
  "${artifact_dir}" \
  "${artifact_zip}"
shasum -a 256 "${artifact_zip}" | tee "${evidence_dir}/artifact-zip-sha256.txt"

cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
repository=${ZMUSIC_REPOSITORY}
commit=${resolved_commit}
project_version=${ZMUSIC_PROJECT_VERSION}
trial_pin=yes
patcher_sha256=${patcher_sha256}
host_os=$(sw_vers -productVersion)
xcode=$(xcodebuild -version | tr '\n' ' ')
iphoneos_sdk=${iphoneos_sdk_version}
deployment_target=15.0
architecture=arm64
linkage=static
dynamic_sndfile=off
dynamic_mpg123=off
fluidsynth=off_pending_ios_glib_strategy
zmusic_target=compiled
api_contract=compiled
physical_execution=not_applicable
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "zmusic-ios-probe: PASS"
