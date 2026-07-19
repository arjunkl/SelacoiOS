#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"

evidence_dir="${repo_root}/build/evidence/m0-host-tools"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"
exec > >(tee "${evidence_dir}/probe.log") 2>&1

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT
trap 'code=$?; printf "FAIL\n" > "${evidence_dir}/result.txt"; echo "host-tools-probe: FAIL at line ${LINENO} (exit ${code})"; exit ${code}' ERR

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: this probe must run on macOS because its outputs are native host executables" >&2
  exit 2
fi

for command_name in git cmake shasum; do
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "error: required command is unavailable: ${command_name}" >&2
    exit 2
  fi
done

echo "== Host environment =="
sw_vers
xcodebuild -version
cmake --version | head -n 1
cc --version | head -n 1

source_dir="${workdir}/GZSelaco"
build_dir="${workdir}/host-tools-build"

echo "== Fetch pinned source =="
git init -q "${source_dir}"
git -C "${source_dir}" remote add origin "${GZSELACO_REPOSITORY}"
git -C "${source_dir}" fetch -q --depth=1 origin "${GZSELACO_COMMIT}"
git -C "${source_dir}" checkout -q --detach FETCH_HEAD
resolved_commit="$(git -C "${source_dir}" rev-parse HEAD)"
[[ "${resolved_commit}" == "${GZSELACO_COMMIT}" ]]
echo "source: ${resolved_commit}"

cmake_generator_args=()
if command -v ninja >/dev/null 2>&1; then
  cmake_generator_args=(-G Ninja)
  echo "generator: Ninja"
else
  echo "generator: default CMake generator"
fi

echo "== Configure native host tools =="
cmake \
  "${cmake_generator_args[@]}" \
  -S "${repo_root}/cmake/host-tools" \
  -B "${build_dir}" \
  -DGZSELACO_SOURCE_DIR="${source_dir}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  2>&1 | tee "${evidence_dir}/configure.log"

cp "${build_dir}/CMakeCache.txt" "${evidence_dir}/CMakeCache.txt"
if [[ -f "${build_dir}/compile_commands.json" ]]; then
  cp "${build_dir}/compile_commands.json" "${evidence_dir}/compile_commands.json"
fi

echo "== Build native host tools =="
cmake --build "${build_dir}" --target selaco-host-tools --parallel 2 \
  2>&1 | tee "${evidence_dir}/build.log"

manifest="${evidence_dir}/host-tools-manifest.txt"
: > "${manifest}"
for tool_name in re2c lemon zipdir; do
  tool_path="$(find "${build_dir}" -type f -name "${tool_name}" -perm -111 -print -quit)"
  if [[ -z "${tool_path}" || ! -x "${tool_path}" ]]; then
    echo "error: expected executable was not produced: ${tool_name}" >&2
    exit 1
  fi
  printf '%s\t%s\n' "${tool_name}" "${tool_path}" | tee -a "${manifest}"
  shasum -a 256 "${tool_path}" | tee -a "${manifest}"
done

re2c_path="$(awk '$1 == "re2c" {print $2; exit}' "${manifest}")"
"${re2c_path}" --version | tee "${evidence_dir}/re2c-version.txt"

printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "host-tools-probe: PASS"
