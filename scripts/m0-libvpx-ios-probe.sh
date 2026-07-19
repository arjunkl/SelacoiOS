#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"
# shellcheck disable=SC1091
source "${repo_root}/DEPENDENCY_TRIAL_PINS.env"

evidence_dir="${repo_root}/build/evidence/m0-libvpx-ios"
artifact_dir="${repo_root}/build/artifacts/m0-libvpx-ios"
rm -rf "${evidence_dir}" "${artifact_dir}"
mkdir -p "${evidence_dir}" "${artifact_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "libvpx-ios-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: libvpx iPhoneOS probe requires macOS and Xcode" >&2
  exit 2
fi

for command_name in git make perl xcrun xcodebuild file nm otool shasum ditto grep; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

for required_var in \
    GZSELACO_REPOSITORY GZSELACO_COMMIT \
    LIBVPX_REPOSITORY LIBVPX_COMMIT LIBVPX_VERSION LIBVPX_VCPKG_PORT_VERSION; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "error: ${required_var} is missing from a source pin file" >&2
    exit 2
  fi
done

vpx_source="${workdir}/libvpx"
gzselaco_source="${workdir}/GZSelaco"
vpx_build="${workdir}/libvpx-build"
vpx_install="${workdir}/libvpx-install"
contract_source="${repo_root}/probes/libvpx-decoder-contract.cpp"
contract_binary="${artifact_dir}/libvpx-decoder-contract"

if [[ ! -f "${contract_source}" ]]; then
  echo "error: libvpx decoder contract is missing" >&2
  exit 2
fi

echo "== Host and SDK environment =="
sw_vers
xcodebuild -version
iphoneos_sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
iphoneos_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version)"
clang_path="$(xcrun --sdk iphoneos --find clang)"
clangxx_path="$(xcrun --sdk iphoneos --find clang++)"
ar_path="$(xcrun --sdk iphoneos --find ar)"
strip_path="$(xcrun --sdk iphoneos --find strip)"
echo "iphoneos SDK path: ${iphoneos_sdk_path}"
echo "iphoneos SDK version: ${iphoneos_sdk_version}"
echo "clang: ${clang_path}"

fetch_exact_commit() {
  local repository="$1"
  local commit="$2"
  local destination="$3"
  git init -q "${destination}"
  git -C "${destination}" remote add origin "${repository}"
  git -C "${destination}" fetch -q --depth=1 origin "${commit}"
  git -C "${destination}" checkout -q --detach FETCH_HEAD
  local resolved
  resolved="$(git -C "${destination}" rev-parse HEAD)"
  if [[ "${resolved}" != "${commit}" ]]; then
    echo "error: ${repository} resolved to ${resolved}, expected ${commit}" >&2
    exit 1
  fi
}

echo "== Fetch exact sources =="
fetch_exact_commit "${LIBVPX_REPOSITORY}" "${LIBVPX_COMMIT}" "${vpx_source}"
fetch_exact_commit "${GZSELACO_REPOSITORY}" "${GZSELACO_COMMIT}" "${gzselaco_source}"

resolved_vpx_version="$("${vpx_source}/build/make/version.sh" --bare "${vpx_source}")"
resolved_vpx_version="${resolved_vpx_version#v}"
echo "resolved libvpx version: ${resolved_vpx_version}"
if [[ "${resolved_vpx_version}" != "${LIBVPX_VERSION}" ]]; then
  echo "error: pinned libvpx reports ${resolved_vpx_version}, expected ${LIBVPX_VERSION}" >&2
  exit 1
fi

mkdir -p "${vpx_build}" "${vpx_install}"

echo "== Inventory pinned GZSelaco libvpx usage =="
{
  grep -RIl --include='*.c' --include='*.cc' --include='*.cpp' --include='*.cxx' --include='*.h' --include='*.hpp' \
    -E '(^|[^A-Za-z0-9_])(vpx_|VPX_)' "${gzselaco_source}" || true
} | sed "s#${gzselaco_source}/##" | sort -u | tee "${evidence_dir}/gzselaco-libvpx-files.txt"
{
  grep -RhoE --include='*.c' --include='*.cc' --include='*.cpp' --include='*.cxx' --include='*.h' --include='*.hpp' \
    '(^|[^A-Za-z0-9_])((vpx|VPX)_[A-Za-z0-9_]+)' "${gzselaco_source}" || true
} | sed -E 's/^[^A-Za-z0-9_]+//' | sort -u | tee "${evidence_dir}/gzselaco-libvpx-tokens.txt"

if [[ ! -s "${evidence_dir}/gzselaco-libvpx-files.txt" ]]; then
  echo "error: no libvpx-consuming source file was found in pinned GZSelaco" >&2
  exit 1
fi

echo "== Configure decoder-only static libvpx for arm64 iPhoneOS =="
export CC="${clang_path}"
export CXX="${clangxx_path}"
export AR="${ar_path}"
export STRIP="${strip_path}"

(
  cd "${vpx_build}"
  "${vpx_source}/configure" \
    --target=arm64-darwin20-gcc \
    --prefix="${vpx_install}" \
    --disable-examples \
    --disable-tools \
    --disable-docs \
    --disable-unit-tests \
    --disable-shared \
    --enable-static \
    --enable-pic \
    --disable-vp8-encoder \
    --disable-vp9-encoder \
    --enable-vp8-decoder \
    --enable-vp9-decoder \
    --disable-webm-io \
    --disable-libyuv \
    --disable-runtime-cpu-detect \
    --extra-cflags="-arch arm64 -isysroot ${iphoneos_sdk_path} -miphoneos-version-min=15.0" \
    --extra-cxxflags="-arch arm64 -isysroot ${iphoneos_sdk_path} -miphoneos-version-min=15.0" \
    --extra-ldflags="-arch arm64 -isysroot ${iphoneos_sdk_path} -miphoneos-version-min=15.0" \
    2>&1 | tee "${evidence_dir}/configure.log"
)

cp "${vpx_build}/config.log" "${evidence_dir}/config.log"
cp "${vpx_build}/vpx_config.h" "${evidence_dir}/vpx_config.h"
cp "${vpx_build}/vpx_config.asm" "${evidence_dir}/vpx_config.asm" 2>/dev/null || true

if ! grep -q '^#define CONFIG_VP8_DECODER 1' "${vpx_build}/vpx_config.h" || \
   ! grep -q '^#define CONFIG_VP9_DECODER 1' "${vpx_build}/vpx_config.h"; then
  echo "error: decoder configuration is absent from generated vpx_config.h" >&2
  exit 1
fi
if grep -q '^#define CONFIG_VP8_ENCODER 1' "${vpx_build}/vpx_config.h" || \
   grep -q '^#define CONFIG_VP9_ENCODER 1' "${vpx_build}/vpx_config.h"; then
  echo "error: encoder code was unexpectedly enabled" >&2
  exit 1
fi

echo "== Build and install libvpx =="
make -C "${vpx_build}" -j3 2>&1 | tee "${evidence_dir}/build.log"
make -C "${vpx_build}" install 2>&1 | tee "${evidence_dir}/install.log"

vpx_library="${vpx_install}/lib/libvpx.a"
if [[ ! -f "${vpx_library}" || ! -f "${vpx_install}/include/vpx/vpx_decoder.h" ]]; then
  echo "error: libvpx library or public decoder headers were not installed" >&2
  exit 1
fi

file "${vpx_library}" | tee "${evidence_dir}/library-file.txt"
xcrun lipo -info "${vpx_library}" | tee "${evidence_dir}/library-architecture.txt"
library_architecture="$(cat "${evidence_dir}/library-architecture.txt")"
if [[ "${library_architecture}" != *"arm64"* || "${library_architecture}" == *"x86_64"* ]]; then
  echo "error: libvpx.a is not physical-device-only arm64" >&2
  exit 1
fi

nm -g "${vpx_library}" > "${evidence_dir}/library-global-symbols.txt"
for symbol in \
    _vpx_codec_vp8_dx _vpx_codec_vp9_dx _vpx_codec_dec_init_ver \
    _vpx_codec_decode _vpx_codec_get_frame _vpx_codec_destroy \
    _vpx_codec_version_str; do
  if ! grep -q "${symbol}" "${evidence_dir}/library-global-symbols.txt"; then
    echo "error: expected decoder symbol is absent: ${symbol}" >&2
    exit 1
  fi
done

if grep -q '_vpx_codec_vp8_cx' "${evidence_dir}/library-global-symbols.txt" || \
   grep -q '_vpx_codec_vp9_cx' "${evidence_dir}/library-global-symbols.txt"; then
  echo "error: encoder interfaces are unexpectedly present" >&2
  exit 1
fi

echo "== Link arm64 iPhoneOS decoder contract =="
"${clangxx_path}" \
  -std=c++17 \
  -arch arm64 \
  -isysroot "${iphoneos_sdk_path}" \
  -miphoneos-version-min=15.0 \
  -I "${vpx_install}/include" \
  "${contract_source}" \
  "${vpx_library}" \
  -o "${contract_binary}" \
  2>&1 | tee "${evidence_dir}/contract-link.log"

file "${contract_binary}" | tee "${evidence_dir}/contract-file.txt"
xcrun lipo -info "${contract_binary}" | tee "${evidence_dir}/contract-architecture.txt"
xcrun vtool -show-build "${contract_binary}" | tee "${evidence_dir}/contract-build-version.txt"
otool -L "${contract_binary}" | tee "${evidence_dir}/contract-linked-libraries.txt"
nm -g "${contract_binary}" > "${evidence_dir}/contract-global-symbols.txt"

if ! grep -q 'platform IOS' "${evidence_dir}/contract-build-version.txt"; then
  echo "error: linked decoder contract is not marked for iOS" >&2
  exit 1
fi
for symbol in _vpx_codec_vp8_dx _vpx_codec_vp9_dx _vpx_codec_decode; do
  if ! grep -q "${symbol}" "${evidence_dir}/contract-global-symbols.txt"; then
    echo "error: decoder contract did not retain linked symbol ${symbol}" >&2
    exit 1
  fi
done

cp "${vpx_library}" "${artifact_dir}/libvpx-ios-arm64.a"
cp -R "${vpx_install}/include/vpx" "${artifact_dir}/vpx-headers"
shasum -a 256 "${artifact_dir}/libvpx-ios-arm64.a" | tee "${evidence_dir}/library-sha256.txt"
shasum -a 256 "${contract_binary}" | tee "${evidence_dir}/contract-sha256.txt"

ditto -c -k --sequesterRsrc --keepParent \
  "${artifact_dir}" \
  "${repo_root}/build/artifacts/libvpx-ios-arm64-probe.zip"
shasum -a 256 "${repo_root}/build/artifacts/libvpx-ios-arm64-probe.zip" | tee "${evidence_dir}/artifact-zip-sha256.txt"

cat > "${evidence_dir}/probe-manifest.txt" <<MANIFEST
repository=${LIBVPX_REPOSITORY}
commit=${LIBVPX_COMMIT}
version=${resolved_vpx_version}
gzselaco_vcpkg_port_version=${LIBVPX_VCPKG_PORT_VERSION}
gzselaco_commit=${GZSELACO_COMMIT}
host_os=$(sw_vers -productVersion)
xcode=$(xcodebuild -version | tr '\n' ' ')
iphoneos_sdk=${iphoneos_sdk_version}
deployment_target=15.0
architecture=arm64
linkage=static
vp8_decoder=enabled
vp9_decoder=enabled
vp8_encoder=disabled
vp9_encoder=disabled
runtime_cpu_detection=disabled
contract=linked_not_executed
MANIFEST

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "libvpx-ios-probe: PASS"
