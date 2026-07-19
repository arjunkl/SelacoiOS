#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"
# shellcheck disable=SC1091
source "${repo_root}/DEPENDENCY_TRIAL_PINS.env"
# shellcheck disable=SC1091
source "${repo_root}/MOLTENVK_PIN.env"

evidence_dir="${repo_root}/build/evidence/m0-full-engine-configure"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "full-engine-configure-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: the full-engine iPhoneOS configure probe requires macOS and Xcode" >&2
  exit 2
fi

for command_name in git python3 cmake xcrun xcodebuild curl tar shasum file; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

platform_stub="${repo_root}/overlays/gzselaco-ios/i_platform_stub.cpp"
gzselaco_patcher="${repo_root}/scripts/patch-gzselaco-ios-m0.py"
zmusic_patcher="${repo_root}/scripts/patch-zmusic-ios-m0.py"
zmusic_stub="${repo_root}/overlays/zmusic-ios/music_fluidsynth_stub.cpp"
for required_file in "${platform_stub}" "${gzselaco_patcher}" "${zmusic_patcher}" "${zmusic_stub}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: committed configure-probe input is missing: ${required_file}" >&2
    exit 2
  fi
done

source_dir="${workdir}/GZSelaco"
zmusic_dir="${workdir}/ZMusic"
host_build_dir="${workdir}/host-tools"
zmusic_build_dir="${workdir}/zmusic-build"
engine_build_dir="${workdir}/engine-build"
moltenvk_tar="${workdir}/${MOLTENVK_ASSET_NAME}"
moltenvk_extract="${workdir}/moltenvk"
mkdir -p "${moltenvk_extract}"

printf '== Host and SDK environment ==\n'
sw_vers
xcodebuild -version
cmake --version | head -n 1
iphoneos_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
iphoneos_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
echo "iphoneos SDK path: ${iphoneos_sdk_path}"
echo "iphoneos SDK version: ${iphoneos_sdk_version}"

printf '== Fetch and patch exact GZSelaco source ==\n'
git init -q "${source_dir}"
git -C "${source_dir}" remote add origin "${GZSELACO_REPOSITORY}"
git -C "${source_dir}" fetch -q --depth=1 origin "${GZSELACO_COMMIT}"
git -C "${source_dir}" checkout -q --detach FETCH_HEAD
resolved_engine_commit="$(git -C "${source_dir}" rev-parse HEAD)"
[[ "${resolved_engine_commit}" == "${GZSELACO_COMMIT}" ]]
python3 "${gzselaco_patcher}" "${source_dir}" "${platform_stub}"
git -C "${source_dir}" diff --check
git -C "${source_dir}" diff --binary > "${evidence_dir}/applied-gzselaco-ios.patch"
gzselaco_patcher_sha256="$(shasum -a 256 "${gzselaco_patcher}" | awk '{print $1}')"

printf '== Build native host generators ==\n'
cmake \
  -S "${repo_root}/cmake/host-tools" \
  -B "${host_build_dir}" \
  -DGZSELACO_SOURCE_DIR="${source_dir}" \
  -DCMAKE_BUILD_TYPE=Release \
  2>&1 | tee "${evidence_dir}/host-tools-configure.log"
cmake --build "${host_build_dir}" --target selaco-host-tools --parallel 3 \
  2>&1 | tee "${evidence_dir}/host-tools-build.log"

import_file="${workdir}/ImportExecutables.cmake"
: > "${import_file}"
for tool_name in re2c lemon zipdir; do
  tool_path="$(find "${host_build_dir}" -type f -name "${tool_name}" -perm -111 -print -quit)"
  if [[ -z "${tool_path}" || ! -x "${tool_path}" ]]; then
    echo "error: native host tool is absent: ${tool_name}" >&2
    exit 1
  fi
  cat >> "${import_file}" <<IMPORT
add_executable(${tool_name} IMPORTED GLOBAL)
set_target_properties(${tool_name} PROPERTIES IMPORTED_LOCATION "${tool_path}")
IMPORT
  printf '%s\t%s\n' "${tool_name}" "${tool_path}" >> "${evidence_dir}/host-tools-manifest.txt"
done
cp "${import_file}" "${evidence_dir}/ImportExecutables.cmake"

printf '== Build pinned static ZMusic dependency ==\n'
git init -q "${zmusic_dir}"
git -C "${zmusic_dir}" remote add origin "${ZMUSIC_REPOSITORY}"
git -C "${zmusic_dir}" fetch -q --depth=1 origin "${ZMUSIC_COMMIT}"
git -C "${zmusic_dir}" checkout -q --detach FETCH_HEAD
resolved_zmusic_commit="$(git -C "${zmusic_dir}" rev-parse HEAD)"
[[ "${resolved_zmusic_commit}" == "${ZMUSIC_COMMIT}" ]]
python3 "${zmusic_patcher}" "${zmusic_dir}" "${zmusic_stub}"
git -C "${zmusic_dir}" diff --check

cmake \
  -G Xcode \
  -S "${zmusic_dir}" \
  -B "${zmusic_build_dir}" \
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
  2>&1 | tee "${evidence_dir}/zmusic-configure.log"
cmake --build "${zmusic_build_dir}" --config Release --target zmusic --parallel 3 \
  2>&1 | tee "${evidence_dir}/zmusic-build.log"
zmusic_library="$(find "${zmusic_build_dir}" -type f -name 'libzmusic.a' -print -quit)"
if [[ -z "${zmusic_library}" || ! -f "${zmusic_library}" ]]; then
  echo "error: full-engine probe did not produce libzmusic.a" >&2
  exit 1
fi

printf '== Resolve pinned MoltenVK iPhoneOS static library ==\n'
moltenvk_url="https://github.com/${MOLTENVK_REPOSITORY}/releases/download/${MOLTENVK_TAG}/${MOLTENVK_ASSET_NAME}"
curl --fail --silent --show-error --location --retry 3 "${moltenvk_url}" --output "${moltenvk_tar}"
moltenvk_sha256="$(shasum -a 256 "${moltenvk_tar}" | awk '{print $1}')"
if [[ "${moltenvk_sha256}" != "${MOLTENVK_ASSET_SHA256}" ]]; then
  echo "error: MoltenVK asset digest differs from committed pin" >&2
  exit 1
fi
tar -xf "${moltenvk_tar}" -C "${moltenvk_extract}"
moltenvk_library="$(find "${moltenvk_extract}" -type f -name 'libMoltenVK.a' -path '*ios-arm64*' ! -path '*simulator*' -print -quit)"
moltenvk_include="$(find "${moltenvk_extract}" -type d -path '*/MoltenVK/include' -print -quit)"
if [[ -z "${moltenvk_library}" || ! -f "${moltenvk_library}" || -z "${moltenvk_include}" ]]; then
  echo "error: pinned MoltenVK package lacks the physical iPhoneOS library or headers" >&2
  exit 1
fi

printf '== Configure full GZSelaco target for arm64 iPhoneOS ==\n'
set +e
cmake \
  -G Xcode \
  -S "${source_dir}" \
  -B "${engine_build_dir}" \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=ONLY \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=ONLY \
  -DFORCE_CROSSCOMPILE=ON \
  -DIMPORT_EXECUTABLES="${import_file}" \
  -DZMUSIC_INCLUDE_DIR="${zmusic_dir}/include" \
  -DZMUSIC_LIBRARIES="${zmusic_library}" \
  -DMOLTENVK_LIBRARY="${moltenvk_library}" \
  -DMOLTENVK_INCLUDE_DIR="${moltenvk_include}" \
  -DNO_OPENAL=ON \
  -DHAVE_VULKAN=ON \
  -DHAVE_GLES2=OFF \
  -DVULKAN_USE_XLIB=OFF \
  -DVULKAN_USE_WAYLAND=OFF \
  -DFORCE_INTERNAL_BZIP2=ON \
  -DSEND_ANON_STATS=OFF \
  -DNO_GTK=ON \
  -DDYN_GTK=OFF \
  -DSELACO_DISABLE_DISCORD_RPC=ON \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
  2>&1 | tee "${evidence_dir}/engine-configure.log"
configure_status=${PIPESTATUS[0]}
set -e

if [[ -f "${engine_build_dir}/CMakeCache.txt" ]]; then
  cp "${engine_build_dir}/CMakeCache.txt" "${evidence_dir}/engine-CMakeCache.txt"
fi

if ! grep -Fq 'SelacoiOS: desktop SDL backend excluded' "${evidence_dir}/engine-configure.log"; then
  echo "error: configure did not enter the iOS SDL exclusion branch" >&2
  exit 1
fi
if ! grep -Fq 'SelacoiOS: selected dedicated iOS platform source set' "${evidence_dir}/engine-configure.log"; then
  echo "error: configure did not select the dedicated iOS source set" >&2
  exit 1
fi
if ! grep -Fq 'Found ZMusic:' "${evidence_dir}/engine-configure.log"; then
  echo "error: full engine did not consume the pinned arm64 ZMusic library" >&2
  exit 1
fi

outcome=""
if [[ "${configure_status}" == "0" ]]; then
  outcome="FULL_CONFIGURE_PASS"
elif grep -Fq 'Could not find libvpx' "${evidence_dir}/engine-configure.log"; then
  outcome="CLASSIFIED_LIBVPX_BOUNDARY"
else
  echo "error: full-engine configure failed outside the approved classified boundary" >&2
  exit "${configure_status}"
fi

echo "outcome=${outcome}" | tee "${evidence_dir}/outcome.txt"
cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
engine_repository=${GZSELACO_REPOSITORY}
engine_commit=${resolved_engine_commit}
engine_patcher_sha256=${gzselaco_patcher_sha256}
zmusic_repository=${ZMUSIC_REPOSITORY}
zmusic_commit=${resolved_zmusic_commit}
moltenvk_tag=${MOLTENVK_TAG}
moltenvk_asset_sha256=${moltenvk_sha256}
host_os=$(sw_vers -productVersion)
xcode=$(xcodebuild -version | tr '\n' ' ')
iphoneos_sdk=${iphoneos_sdk_version}
deployment_target=15.0
architecture=arm64
host_tools=imported_native_macos
platform_source_set=dedicated_ios
cocoa_backend=excluded
sdl_desktop_backend=excluded
openal=disabled
vm_jit=disabled_by_arm64
vulkan=enabled
moltenvk=static_pinned
zmusic=static_pinned_without_fluidsynth
configure_status=${configure_status}
outcome=${outcome}
compile=not_started
link=not_started
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "full-engine-configure-probe: PASS (${outcome})"
