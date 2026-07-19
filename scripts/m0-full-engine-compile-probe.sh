#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m0-full-engine-configure-probe.sh"
vulkan_only_patcher="${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py"
evidence_dir="${repo_root}/build/evidence/m0-full-engine-compile"
rm -rf "${evidence_dir}"
mkdir -p "${evidence_dir}"

for required_file in "${source_probe}" "${vulkan_only_patcher}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: full-engine compile input is missing: ${required_file}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

driver="${workdir}/full-engine-compile-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

text = text.replace(
    'build/evidence/m0-full-engine-configure',
    'build/evidence/m0-full-engine-compile',
    1,
)
text = text.replace(
    'full-engine-configure-probe:',
    'full-engine-compile-probe:',
)

main_patch_call = 'python3 "${gzselaco_patcher}" "${source_dir}" "${platform_stub}"\n'
if text.count(main_patch_call) != 1:
    raise SystemExit("configure probe no longer exposes the expected GZSelaco patch call")
text = text.replace(
    main_patch_call,
    main_patch_call
    + 'python3 "${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py" "${source_dir}"\n',
    1,
)

configure_command = "printf '== Configure full GZSelaco target for arm64 iPhoneOS ==\\n'\n"
if text.count(configure_command) != 1:
    raise SystemExit("configure probe no longer exposes the expected configure command")
text = text.replace(
    configure_command,
    "if ! grep -Fq 'SelacoiOS: desktop OpenGL renderer sources excluded' "
    '"${source_dir}/src/CMakeLists.txt"; then\n'
    '  echo "error: Vulkan-only iOS source patch was not applied" >&2\n'
    '  exit 1\n'
    'fi\n\n'
    + configure_command,
    1,
)

marker = 'outcome="FULL_CONFIGURE_PASS"\n'
if text.count(marker) != 1:
    raise SystemExit("configure probe no longer exposes the expected compile insertion marker")

compile_block = r'''printf '== Compile full GZSelaco target for arm64 iPhoneOS ==\n'
trap - ERR
set +e
cmake --build "${engine_build_dir}" \
  --config Release \
  --target zdoom \
  --parallel 1 \
  2>&1 | tee "${evidence_dir}/engine-build.log"
compile_status=${PIPESTATUS[0]}
set -e
trap 'fail_probe $? ${LINENO}' ERR

compile_manifest="passed"
link_manifest="passed"
if [[ "${compile_status}" == "0" ]]; then
  outcome="FULL_COMPILE_PASS"
else
  compile_manifest="failed_boundary_captured"
  link_manifest="not_reached"
  python3 - "${evidence_dir}/engine-build.log" "${evidence_dir}/first-compile-boundary.txt" <<'BOUNDARY'
from __future__ import annotations

import pathlib
import re
import sys

log_path = pathlib.Path(sys.argv[1])
output_path = pathlib.Path(sys.argv[2])
lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
source_error = re.compile(
    r"(?:^|\s)([^:\s]+\.(?:c|cc|cpp|cxx|m|mm|h|hh|hpp|hxx)):(\d+)(?::(\d+))?:\s+(?:fatal\s+)?error:"
)
match_index = None
match = None
for index, line in enumerate(lines):
    candidate = source_error.search(line)
    if candidate:
        match_index = index
        match = candidate
        break

if match_index is None or match is None:
    generic = next(
        (index for index, line in enumerate(lines) if " error:" in line or "fatal error:" in line),
        None,
    )
    if generic is None:
        raise SystemExit("build failed without a compiler diagnostic")
    start = max(0, generic - 15)
    end = min(len(lines), generic + 25)
    output_path.write_text(
        "classification=UNCLASSIFIED_BUILD_ERROR\n"
        + "\n".join(lines[start:end])
        + "\n",
        encoding="utf-8",
    )
    raise SystemExit("build failure was not a source or header compiler diagnostic")

start = max(0, match_index - 15)
end = min(len(lines), match_index + 35)
output_path.write_text(
    "classification=TRANSLATION_UNIT_COMPILE_BOUNDARY\n"
    f"source={match.group(1)}\n"
    f"line={match.group(2)}\n"
    f"column={match.group(3) or ''}\n"
    + "\n".join(lines[start:end])
    + "\n",
    encoding="utf-8",
)
BOUNDARY
  outcome="CLASSIFIED_TRANSLATION_UNIT_BOUNDARY"
fi
'''
text = text.replace(marker, compile_block, 1)
text = text.replace('compile=not_started', 'compile=${compile_manifest}', 1)
text = text.replace('link=not_started', 'link=${link_manifest}', 1)
text = text.replace(
    'echo "full-engine-compile-probe: PASS (${outcome})"',
    'echo "full-engine-compile-probe: PASS (${outcome}; compile_status=${compile_status})"',
    1,
)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

cp "${driver}" "${evidence_dir}/generated-compile-driver.sh"
bash -n "${driver}"
bash "${driver}"
