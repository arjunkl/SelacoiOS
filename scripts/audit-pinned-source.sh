#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"

for required_var in GZSELACO_REPOSITORY GZSELACO_COMMIT GZSELACO_UPSTREAM_BRANCH; do
  if [[ -z "${!required_var:-}" ]]; then
    echo "error: ${required_var} is missing from SOURCE_PIN.env" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
source_dir="${workdir}/GZSelaco"

echo "Fetching pinned GZSelaco commit ${GZSELACO_COMMIT}..."
git init -q "${source_dir}"
git -C "${source_dir}" remote add origin "${GZSELACO_REPOSITORY}"
git -C "${source_dir}" fetch -q --depth=1 origin "${GZSELACO_COMMIT}"
git -C "${source_dir}" checkout -q --detach FETCH_HEAD

resolved_commit="$(git -C "${source_dir}" rev-parse HEAD)"
if [[ "${resolved_commit}" != "${GZSELACO_COMMIT}" ]]; then
  echo "error: source pin resolved to ${resolved_commit}, expected ${GZSELACO_COMMIT}" >&2
  exit 1
fi

assert_contains() {
  local file="$1"
  local text="$2"
  local description="$3"

  if ! grep -Fq -- "${text}" "${source_dir}/${file}"; then
    echo "error: pinned source no longer satisfies assumption: ${description}" >&2
    echo "       expected '${text}' in ${file}" >&2
    exit 1
  fi
  echo "verified: ${description}"
}

assert_contains "CMakeLists.txt" 'set(CMAKE_CXX_STANDARD 17)' "C++17 build baseline"
assert_contains "CMakeLists.txt" 'option( FORCE_CROSSCOMPILE' "explicit cross-compilation switch"
assert_contains "CMakeLists.txt" 'option (HAVE_VULKAN "Enable Vulkan support" ON)' "Vulkan renderer build option"
assert_contains "CMakeLists.txt" 'if( ${TARGET_ARCHITECTURE} MATCHES "x86_64" )' "VM JIT restricted to x86_64 by default"
assert_contains "src/version.h" '#define GAMESIG "SELACO"' "Selaco-specific game signature"
assert_contains "src/version.h" '#define ENG_MAJOR 4' "declared GZDoom engine lineage"
assert_contains "src/version.h" '#define ENG_MINOR 13' "GZDoom 4.13 engine baseline"

platform_ios_count="$(git -C "${source_dir}" ls-files | grep -E -i '(^|/)(ios|iphone)(/|\.|_)' | wc -l | tr -d ' ')"
if [[ "${platform_ios_count}" == "0" ]]; then
  echo "observed: no dedicated iOS platform layer is present in the pinned source"
else
  echo "observed: ${platform_ios_count} path(s) appear iOS-specific; review before transplant work"
fi

tracked_files="$(git -C "${source_dir}" ls-files | wc -l | tr -d ' ')"
echo "source-audit: PASS (${tracked_files} tracked files at ${resolved_commit})"
