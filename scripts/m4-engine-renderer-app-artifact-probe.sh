#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4-engine-init-app-artifact-probe.sh"
renderer_compile_probe="${repo_root}/scripts/m4-engine-renderer-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m4-engine-renderer-app"
artifact_dir="${repo_root}/build/artifacts/m4-engine-renderer-app"

for required_file in "${source_probe}" "${renderer_compile_probe}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: Milestone 4B app input is missing: ${required_file}" >&2
    exit 2
  fi
done

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
fail_probe() {
  local code="$1"
  local line="$2"
  mkdir -p "${evidence_dir}"
  printf 'FAIL\n' > "${evidence_dir}/result.txt"
  echo "engine-renderer-app-probe: FAIL at line ${line} (exit ${code})"
  exit "${code}"
}
trap cleanup EXIT
trap 'fail_probe $? ${LINENO}' ERR

driver="${workdir}/m4-engine-renderer-app-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

replacements = {
    "build/evidence/m4-engine-init-app": "build/evidence/m4-engine-renderer-app",
    "build/artifacts/m4-engine-init-app": "build/artifacts/m4-engine-renderer-app",
    "build/work/m4-engine-init-app": "build/work/m4-engine-renderer-app",
    "build/evidence/m4-engine-init-compile": "build/evidence/m4-engine-renderer-compile",
    "scripts/m4-engine-init-compile-probe.sh":
        "scripts/m4-engine-renderer-compile-probe.sh",
    "engine-init-app-probe:": "engine-renderer-app-probe:",
    '"CFBundleShortVersionString": "0.6.0"': '"CFBundleShortVersionString": "0.7.0"',
    '"CFBundleVersion": "6"': '"CFBundleVersion": "7"',
    'if [[ "${bundle_short_version}" != "0.6.0" || "${bundle_version}" != "6" ]]; then':
        'if [[ "${bundle_short_version}" != "0.7.0" || "${bundle_version}" != "7" ]]; then',
    'echo "bundle_version=${bundle_short_version}(${bundle_version})"':
        'echo "bundle_version=${bundle_short_version}(${bundle_version})"',
}
for old, new in replacements.items():
    if old not in text:
        raise SystemExit(f"Milestone 4 app probe marker changed: {old}")
    text = text.replace(old, new)

old_symbols = (
    "for retained_symbol in _main _UIApplicationMain _Args _Video _PerfToSec "
    "_SelacoIOSM4RendererStrategy; do"
)
new_symbols = (
    "for retained_symbol in _main _UIApplicationMain _Args _Video _PerfToSec "
    "_SelacoIOSM4RendererStrategy _SelacoIOSPrepareEngineRendererHandoff "
    "_SelacoIOSGetVkGetInstanceProcAddr __Z14gl_CreateVideov __Z14I_InitGraphicsv; do"
)
if text.count(old_symbols) != 1:
    raise SystemExit("Milestone 4 retained-symbol validator changed")
text = text.replace(old_symbols, new_symbols, 1)

old_markers = '''for required_marker in \\
  'SelacoiOS Milestone 4' \\
  'engine_init_boundary_reached' \\
  'engine-init-status.txt' \\
  'renderer-init-status.txt' \\
  'renderer_creation_deferred' \\
  'M4A stop-before-renderer' \\
  'V_Init2'; do'''
new_markers = '''for required_marker in \\
  'SelacoiOS Milestone 4' \\
  'engine-init-status.txt' \\
  'renderer-init-status.txt' \\
  'M4B diagnostic-to-engine handoff' \\
  'renderer_handoff_passed' \\
  'engine_vulkan_instance_create_entered' \\
  'engine_metal_surface_create_passed' \\
  'v_init2_passed' \\
  'menu_init_passed' \\
  'title_loop_started' \\
  'engine_loop_entered' \\
  'engine_first_frame_presented'; do'''
if text.count(old_markers) != 1:
    raise SystemExit("Milestone 4 runtime-marker validator changed")
text = text.replace(old_markers, new_markers, 1)

text = text.replace(
    "runtime_status_ui=swapchain_plus_m4a_engine_initialization",
    "runtime_status_ui=diagnostic_swapchain_handoff_to_engine_renderer_and_title",
)
text = text.replace(
    "engine_stop_boundary=immediately_before_V_Init2",
    "engine_target_boundary=first_engine_present_and_title_menu",
)
text = text.replace(
    "renderer_ownership=diagnostic_presenter_only",
    "renderer_ownership=diagnostic_destroyed_then_engine_owned",
)
text = text.replace(
    "renderer_strategy=stop_before_V_Init2_diagnostic_presenter_remains_owner",
    "renderer_strategy=destroy_diagnostic_then_create_engine_vulkan",
)
text = text.replace(
    "runtime_lifecycle=uikit_swapchain_plus_m4a_engine_init_not_executed",
    "runtime_lifecycle=uikit_diagnostic_handoff_plus_engine_renderer_not_executed",
)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"

# The app/IPA identity deliberately stays stable so iOS updates the existing
# SelacoiOS Engine Init container instead of creating another Files folder.
engine_app="${artifact_dir}/Selaco-engine-init-probe-unsigned.app"
engine_binary="${engine_app}/Selaco"
if [[ ! -f "${engine_binary}" ]]; then
  echo "error: Milestone 4B stable Engine Init app was not produced" >&2
  exit 1
fi

strings "${engine_binary}" > "${evidence_dir}/m4b-runtime-strings.txt"
for marker in \
  'M4B diagnostic-to-engine handoff' \
  'renderer_handoff_passed' \
  'engine_first_frame_presented' \
  'title_loop_started'; do
  grep -Fq "${marker}" "${evidence_dir}/m4b-runtime-strings.txt"
done

echo "stable_bundle_identifier=am.arjunkl.selacoios.engineinit.m4" >> "${evidence_dir}/probe-manifest.txt"
echo "stable_files_container=SelacoiOS Engine Init" >> "${evidence_dir}/probe-manifest.txt"
echo "new_app_identity_allocated=no" >> "${evidence_dir}/probe-manifest.txt"
echo "physical_execution=not_tested" >> "${evidence_dir}/probe-manifest.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "engine-renderer-app-probe: PASS"
