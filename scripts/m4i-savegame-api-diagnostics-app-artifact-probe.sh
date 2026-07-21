#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4-title-menu-app-artifact-probe.sh"
compile_probe="${repo_root}/scripts/m4i-savegame-api-compile-probe.sh"
evidence_dir="${repo_root}/build/evidence/m4-title-menu-app"
artifact_dir="${repo_root}/build/artifacts/m4-title-menu-app"
app="${artifact_dir}/Selaco-engine-init-probe-unsigned.app"
binary="${app}/Selaco"
public_support="${app}/gzdoom.pk3"
info_plist="${app}/Info.plist"
app_zip="${artifact_dir}/Selaco-engine-init-probe-unsigned-app.zip"
ipa="${artifact_dir}/Selaco-engine-init-probe-unsigned.ipa"
checkpoint_file="${evidence_dir}/m4i-wrapper-checkpoints.txt"

for required in "${source_probe}" "${compile_probe}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4I source input is missing: ${required}" >&2
    exit 2
  fi
done

driver_dir="$(mktemp -d)"
package_root=""
cleanup() {
  rm -rf "${driver_dir}"
  if [[ -n "${package_root}" ]]; then
    rm -rf "${package_root}"
  fi
}
trap cleanup EXIT

mkdir -p "${evidence_dir}" "${artifact_dir}"
echo "checkpoint=m4i_wrapper_started" > "${checkpoint_file}"

# Build a local title/menu driver that swaps in the M4I compile chain and drops
# only the obsolete M4F public-signature assertion. All renderer, registry,
# ZScript-log, bundle, dependency, and proprietary-data validators remain.
base_probe="${driver_dir}/m4i-base-app-probe.sh"
python3 - "${source_probe}" "${base_probe}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

compile_old = "scripts/m4-title-menu-compile-probe.sh"
compile_new = "scripts/m4i-savegame-api-compile-probe.sh"
if text.count(compile_old) != 1:
    raise SystemExit("M4I title-menu compile-probe marker changed")
text = text.replace(compile_old, compile_new, 1)

compile_evidence_old = "build/evidence/m4-title-menu-compile"
compile_evidence_new = "build/evidence/m4i-savegame-api-compile"
if text.count(compile_evidence_old) != 1:
    raise SystemExit("M4I title-menu compile-evidence marker changed")
text = text.replace(compile_evidence_old, compile_evidence_new, 1)

old = r'''unzip -p "${public_support}" zscript/events.zs > "${evidence_dir}/m4f-public-events.zs"
for marker in \
  'SELACO_IOS_M4F_RETAIL_SAVEGAME_VIRTUALS' \
  'virtual int GetSavegameFlags()' \
  'virtual String GetSavegameTitle()'; do
  grep -Fq "${marker}" "${evidence_dir}/m4f-public-events.zs"
done

'''
new = r'''unzip -p "${public_support}" zscript/events.zs > "${evidence_dir}/m4f-public-events.zs"

'''
if text.count(old) != 1:
    raise SystemExit("M4I predecessor public-support validator changed")
text = text.replace(old, new, 1)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${base_probe}"
bash "${base_probe}"
echo "checkpoint=base_probe_passed" >> "${checkpoint_file}"

# The inherited app probe may preserve only the validated app ZIP.
if [[ ! -f "${binary}" || ! -f "${public_support}" || ! -f "${info_plist}" ]]; then
  if [[ ! -f "${app_zip}" ]]; then
    echo "error: M4I base probe produced neither a live app nor an app ZIP" >&2
    exit 1
  fi
  app_extract="${driver_dir}/app-extract"
  mkdir -p "${app_extract}"
  ditto -x -k "${app_zip}" "${app_extract}"
  extracted_app="$(find "${app_extract}" -type d -name '*.app' -print -quit)"
  if [[ -z "${extracted_app}" ]]; then
    echo "error: M4I app ZIP contains no .app bundle" >&2
    exit 1
  fi
  rm -rf "${app}"
  ditto "${extracted_app}" "${app}"
  echo "checkpoint=app_rematerialized_from_zip" >> "${checkpoint_file}"
else
  echo "checkpoint=live_app_available" >> "${checkpoint_file}"
fi

for required in "${binary}" "${public_support}" "${info_plist}"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4I prerequisite artifact is missing after app recovery: ${required}" >&2
    exit 1
  fi
done
echo "checkpoint=app_inputs_validated" >> "${checkpoint_file}"

strings "${binary}" > "${evidence_dir}/m4i-runtime-strings.txt"
for marker in \
  'SELACO_IOS_M4I class=' \
  'SELACO_IOS_M4I caller_class=' \
  'actual_count=' \
  'expected_types=' \
  'actual_types=' \
  'zscript-compile.log' \
  'actor_zscript_compile_entered'; do
  grep -Fq "${marker}" "${evidence_dir}/m4i-runtime-strings.txt"
done
echo "checkpoint=runtime_markers_validated" >> "${checkpoint_file}"

unzip -p "${public_support}" zscript/events.zs > "${evidence_dir}/m4i-public-events.zs"
for marker in \
  'SELACO_IOS_M4H_RETAIL_SAVEGAME_SIGNATURES' \
  'virtual int GetSavegameFlags(bool quicksave, bool autosave)' \
  'virtual String, Int GetSavegameTitle(int type)'; do
  grep -Fq "${marker}" "${evidence_dir}/m4i-public-events.zs"
done
if grep -Fq 'virtual int GetSavegameFlags()' "${evidence_dir}/m4i-public-events.zs" || \
   grep -Fq 'virtual String GetSavegameTitle()' "${evidence_dir}/m4i-public-events.zs"; then
  echo "error: M4I public support archive regressed to guessed savegame prototypes" >&2
  exit 1
fi
echo "checkpoint=exact_public_signatures_validated" >> "${checkpoint_file}"

/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.7.9' "${info_plist}"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 16' "${info_plist}"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
if [[ "${bundle_id}" != "am.arjunkl.selacoios.engineinit.m4" || \
      "${short_version}" != "0.7.9" || "${build_version}" != "16" ]]; then
  echo "error: M4I stable app identity/version validation failed" >&2
  exit 1
fi
echo "checkpoint=version_updated" >> "${checkpoint_file}"

rm -f "${app_zip}" "${ipa}"
ditto -c -k --sequesterRsrc --keepParent "${app}" "${app_zip}"
package_root="$(mktemp -d)"
mkdir -p "${package_root}/Payload"
ditto "${app}" "${package_root}/Payload/Selaco.app"
(
  cd "${package_root}"
  zip -qry "${ipa}" Payload
)

unzip -l "${ipa}" > "${evidence_dir}/m4i-ipa-inventory.txt"
if grep -Eiq '(^|/)(Selaco\.ipk3|[^/]+\.mobileprovision|[^/]+\.p12)$' \
    "${evidence_dir}/m4i-ipa-inventory.txt"; then
  echo "error: M4I IPA contains licensed data or signing material" >&2
  exit 1
fi
echo "checkpoint=ipa_validated" >> "${checkpoint_file}"

{
  echo "m4i_savegame_api_diagnostics=ownership_context_and_call_contract"
  echo "unknown_identifier_fields=class,function,self"
  echo "excess_argument_fields=caller_class,caller_function,target_class,actual_count,declared_explicit,implicit,expected_types,actual_types"
  echo "m4h_retail_savegame_signatures=retained_exact"
  echo "stable_bundle_identifier=${bundle_id}"
  echo "stable_files_container=SelacoiOS Engine Init"
  echo "bundle_version=${short_version}(${build_version})"
  echo "commercial_asset_in_ci=no"
  echo "private_script_source_logged=no"
  echo "physical_execution=not_tested"
} >> "${evidence_dir}/probe-manifest.txt"

shasum -a 256 "${ipa}" > "${evidence_dir}/m4i-ipa-sha256.txt"
stat -f '%z' "${ipa}" > "${evidence_dir}/m4i-ipa-size.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
echo "checkpoint=m4i_package_passed" >> "${checkpoint_file}"
echo "m4i-savegame-api-diagnostics-app-probe: PASS"
