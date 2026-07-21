#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4-engine-init-app-artifact-probe.sh"
title_menu_compile_probe="${repo_root}/scripts/m4-title-menu-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m4-title-menu-app"
artifact_dir="${repo_root}/build/artifacts/m4-title-menu-app"

for required_file in "${source_probe}" "${title_menu_compile_probe}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "error: Milestone 4D app input is missing: ${required_file}" >&2
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
  echo "title-menu-app-probe: FAIL at line ${line} (exit ${code})"
  exit "${code}"
}
trap cleanup EXIT
trap 'fail_probe $? ${LINENO}' ERR

driver="${workdir}/m4-title-menu-app-driver.sh"
python3 - "${source_probe}" "${driver}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source_path = pathlib.Path(sys.argv[1])
driver_path = pathlib.Path(sys.argv[2])
text = source_path.read_text(encoding="utf-8")

replacements = {
    "build/evidence/m4-engine-init-app": "build/evidence/m4-title-menu-app",
    "build/artifacts/m4-engine-init-app": "build/artifacts/m4-title-menu-app",
    "build/work/m4-engine-init-app": "build/work/m4-title-menu-app",
    "build/evidence/m4-engine-init-compile": "build/evidence/m4-title-menu-compile",
    "scripts/m4-engine-init-compile-probe.sh":
        "scripts/m4-title-menu-compile-probe.sh",
    "engine-init-app-probe:": "title-menu-app-probe:",
    '"CFBundleShortVersionString": "0.6.0"': '"CFBundleShortVersionString": "0.7.4"',
    '"CFBundleVersion": "6"': '"CFBundleVersion": "11"',
    'if [[ "${bundle_short_version}" != "0.6.0" || "${bundle_version}" != "6" ]]; then':
        'if [[ "${bundle_short_version}" != "0.7.4" || "${bundle_version}" != "11" ]]; then',
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
    "_SelacoIOSM4RendererStrategy _SelacoIOSRegisterEngineMetalLayer "
    "_SelacoIOSM4CTitleMenuClosure _gl_dither_bpc _gl_multisample "
    "__Z14I_InitGraphicsv; do"
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
  'M4C title/menu closure' \\
  'title_menu_closure_selected' \\
  'renderer_handoff_passed' \\
  'engine_volk_dispatch_ready' \\
  'engine_portability_extension_optional' \\
  'native_class_registry_passed' \\
  'native_class_registry_failed' \\
  'native_startup_window_bypassed' \\
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
    "runtime_status_ui=engine_owned_renderer_title_menu_candidate",
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
    "runtime_lifecycle=uikit_handoff_engine_renderer_title_menu_not_executed",
)

driver_path.write_text(text, encoding="utf-8")
driver_path.chmod(0o755)
PY

bash -n "${driver}"
bash "${driver}"

# Keep the same app identity and artifact file name so installation updates the
# existing Engine Init app and preserves Documents/Selaco/Selaco.ipk3.
engine_app="${artifact_dir}/Selaco-engine-init-probe-unsigned.app"
engine_binary="${engine_app}/Selaco"
if [[ ! -f "${engine_binary}" ]]; then
  echo "error: Milestone 4D stable Engine Init app was not produced" >&2
  exit 1
fi

strings "${engine_binary}" > "${evidence_dir}/m4d-runtime-strings.txt"
for marker in \
  'M4C title/menu closure' \
  'title_menu_closure_selected' \
  'native_startup_window_bypassed' \
  'renderer_handoff_passed' \
  'engine_volk_dispatch_ready' \
  'engine_portability_extension_optional' \
  'native_class_registry_passed' \
  'native_class_registry_failed' \
  'engine_first_frame_presented' \
  'title_loop_started'; do
  grep -Fq "${marker}" "${evidence_dir}/m4d-runtime-strings.txt"
done

otool -l "${engine_binary}" > "${evidence_dir}/m4d-mach-o-load-commands.txt"
python3 - "${evidence_dir}/m4d-mach-o-load-commands.txt" \
  "${evidence_dir}/m4d-creg-section.txt" <<'PY'
from __future__ import annotations

import pathlib
import sys

load_commands = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
lines = load_commands.splitlines()
matches: list[tuple[str, int]] = []
for index, line in enumerate(lines):
    if line.strip() != "sectname creg":
        continue
    segment = "unknown"
    size = 0
    for detail in lines[index + 1:index + 12]:
        parts = detail.split()
        if len(parts) == 2 and parts[0] == "segname":
            segment = parts[1]
        elif len(parts) == 2 and parts[0] == "size":
            size = int(parts[1], 16)
    matches.append((segment, size))

if not matches:
    raise SystemExit("final Mach-O does not contain a creg section")
if not any(size > 0 for _, size in matches):
    raise SystemExit("final Mach-O creg section is empty")

output = pathlib.Path(sys.argv[2])
output.write_text(
    "\n".join(f"segment={segment} size={size}" for segment, size in matches) + "\n",
    encoding="utf-8",
)
PY

cat "${evidence_dir}/m4d-creg-section.txt"
echo "stable_bundle_identifier=am.arjunkl.selacoios.engineinit.m4" >> "${evidence_dir}/probe-manifest.txt"
echo "stable_files_container=SelacoiOS Engine Init" >> "${evidence_dir}/probe-manifest.txt"
echo "bundle_version=0.7.4(11)" >> "${evidence_dir}/probe-manifest.txt"
echo "input_backend=inert_title_menu_only" >> "${evidence_dir}/probe-manifest.txt"
echo "vr_backend=disabled" >> "${evidence_dir}/probe-manifest.txt"
echo "statistics_transport=disabled" >> "${evidence_dir}/probe-manifest.txt"
echo "vulkan_loader=zvulkan_target_uses_embedded_moltenvk" >> "${evidence_dir}/probe-manifest.txt"
echo "portability_enumeration=optional_enable_if_advertised" >> "${evidence_dir}/probe-manifest.txt"
echo "native_class_registry=mach_o_creg_retained_and_nonempty" >> "${evidence_dir}/probe-manifest.txt"
echo "new_app_identity_allocated=no" >> "${evidence_dir}/probe-manifest.txt"
echo "physical_execution=not_tested" >> "${evidence_dir}/probe-manifest.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
trap - ERR
echo "title-menu-app-probe: PASS"
