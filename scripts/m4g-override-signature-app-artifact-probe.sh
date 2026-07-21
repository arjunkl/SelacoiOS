#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
base_probe="${repo_root}/scripts/m4-title-menu-app-artifact-probe.sh"
evidence_dir="${repo_root}/build/evidence/m4-title-menu-app"
artifact_dir="${repo_root}/build/artifacts/m4-title-menu-app"
app="${artifact_dir}/Selaco-engine-init-probe-unsigned.app"
binary="${app}/Selaco"
info_plist="${app}/Info.plist"
app_zip="${artifact_dir}/Selaco-engine-init-probe-unsigned-app.zip"
ipa="${artifact_dir}/Selaco-engine-init-probe-unsigned.ipa"

if [[ ! -f "${base_probe}" ]]; then
  echo "error: M4G base app probe is missing: ${base_probe}" >&2
  exit 2
fi

bash "${base_probe}"

for required in "${binary}" "${info_plist}" "${app}/gzdoom.pk3"; do
  if [[ ! -f "${required}" ]]; then
    echo "error: M4G prerequisite artifact is missing: ${required}" >&2
    exit 1
  fi
done

/usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.7.7' "${info_plist}"
/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 14' "${info_plist}"

bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info_plist}")"
short_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${info_plist}")"
build_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${info_plist}")"
if [[ "${bundle_id}" != "am.arjunkl.selacoios.engineinit.m4" || \
      "${short_version}" != "0.7.7" || "${build_version}" != "14" ]]; then
  echo "error: M4G stable app identity/version validation failed" >&2
  exit 1
fi

strings "${binary}" > "${evidence_dir}/m4g-runtime-strings.txt"
grep -Fq 'SELACO_IOS_M4G class=' "${evidence_dir}/m4g-runtime-strings.txt"
grep -Fq 'zscript-compile.log' "${evidence_dir}/m4g-runtime-strings.txt"
grep -Fq 'actor_zscript_compile_entered' "${evidence_dir}/m4g-runtime-strings.txt"

# Repackage after the build-number update while preserving the established app
# and IPA filenames used by the stable Engine Init workflow.
rm -f "${app_zip}" "${ipa}"
ditto -c -k --sequesterRsrc --keepParent "${app}" "${app_zip}"
package_root="$(mktemp -d)"
cleanup() {
  rm -rf "${package_root}"
}
trap cleanup EXIT
mkdir -p "${package_root}/Payload"
ditto "${app}" "${package_root}/Payload/Selaco.app"
(
  cd "${package_root}"
  zip -qry "${ipa}" Payload
)

unzip -l "${ipa}" > "${evidence_dir}/m4g-ipa-inventory.txt"
if grep -Eiq '(^|/)(Selaco\.ipk3|[^/]+\.mobileprovision|[^/]+\.p12)$' \
    "${evidence_dir}/m4g-ipa-inventory.txt"; then
  echo "error: M4G IPA contains licensed data or signing material" >&2
  exit 1
fi

{
  echo "m4g_override_signature_diagnostics=retained"
  echo "diagnostic_fields=class,parent,returns,args,implicit,flags"
  echo "stable_bundle_identifier=${bundle_id}"
  echo "stable_files_container=SelacoiOS Engine Init"
  echo "bundle_version=${short_version}(${build_version})"
  echo "commercial_asset_in_ci=no"
  echo "physical_execution=not_tested"
} >> "${evidence_dir}/probe-manifest.txt"

shasum -a 256 "${ipa}" > "${evidence_dir}/m4g-ipa-sha256.txt"
stat -f '%z' "${ipa}" > "${evidence_dir}/m4g-ipa-size.txt"
printf 'PASS\n' > "${evidence_dir}/result.txt"
echo "m4g-override-signature-app-probe: PASS"
