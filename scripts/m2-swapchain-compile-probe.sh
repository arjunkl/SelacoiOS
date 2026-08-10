#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-compile-probe.sh"
runtime_patcher="${repo_root}/scripts/patch-gzselaco-runtime-bootstrap-ios-m1.py"
swapchain_patcher="${repo_root}/scripts/patch-gzselaco-swapchain-ios-m2.py"
runtime_overlay="${repo_root}/overlays/gzselaco-ios/i_runtime_bootstrap.mm"
swapchain_overlay="${repo_root}/overlays/gzselaco-ios/i_swapchain_probe.mm"
evidence_dir="${repo_root}/build/evidence/m2-swapchain-compile"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"

for required_file in \
  "${source_probe}" \
  "${runtime_patcher}" \
  "${swapchain_patcher}" \
  "${runtime_overlay}" \
  "${swapchain_overlay}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: Milestone 2 compile input is missing: ${required_file}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/m2-swapchain-compile-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

text = text.replace(
    "build/evidence/m0-full-engine-compile",
    "build/evidence/m2-swapchain-compile",
)

old = (
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py\" "
    "\"${source_dir}\"\\n',\n"
)
new = (
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py\" "
    "\"${source_dir}\"\\n'\n"
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-runtime-bootstrap-ios-m1.py\" "
    "\"${source_dir}\"\\n'\n"
    "    + 'python3 \"${repo_root}/scripts/patch-gzselaco-swapchain-ios-m2.py\" "
    "\"${source_dir}\"\\n',\n"
)
if text.count(old) != 1:
    raise SystemExit(
        "Milestone 0 compile probe no longer exposes the expected Vulkan patch insertion"
    )
text = text.replace(old, new, 1)

configure_read_marker = 'text = source_path.read_text(encoding="utf-8")\n\n'
if text.count(configure_read_marker) != 1:
    raise SystemExit("Milestone 0 compile probe configure-reader marker changed")

dynamic_framework_transform = r'''dynamic_anchor = 'moltenvk_include="$(find "${moltenvk_extract}" -type d -path \'*/MoltenVK/include\' -print -quit)"\n'
if text.count(dynamic_anchor) != 1:
    raise SystemExit("configure probe MoltenVK include resolution changed")
text = text.replace(
    dynamic_anchor,
    dynamic_anchor
    + 'moltenvk_dynamic_framework="$(find "${moltenvk_extract}" -type d -name \'MoltenVK.framework\' -path \'*dynamic*\' -path \'*ios-arm64*\' ! -path \'*simulator*\' -print -quit)"\n',
    1,
)

moltenvk_argument = '  -DMOLTENVK_LIBRARY="${moltenvk_library}" \\\n'
if text.count(moltenvk_argument) != 1:
    raise SystemExit("configure probe MoltenVK CMake argument changed")
text = text.replace(
    moltenvk_argument,
    moltenvk_argument
    + '  -DMOLTENVK_DYNAMIC_FRAMEWORK="${moltenvk_dynamic_framework}" \\\n',
    1,
)

'''
text = text.replace(
    configure_read_marker,
    configure_read_marker + dynamic_framework_transform,
    1,
)

text = text.replace(
    "full-engine-compile-probe:",
    "swapchain-compile-probe:",
)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

cp "${driver}" "${evidence_dir}/generated-swapchain-compile-driver.sh"
bash -n "${driver}"
bash "${driver}"
