#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
source "${repo_root}/SOURCE_PIN.env"

analysis_root="${repo_root}/.codebase-memory-worktree"
engine_root="${analysis_root}/GZSelaco-M4L"

if [[ -e "${engine_root}" ]]; then
  echo "error: analysis tree already exists: ${engine_root}" >&2
  echo "move it aside or pass its path directly to Codebase Memory" >&2
  exit 2
fi

mkdir -p "${analysis_root}"

git init -q "${engine_root}"
git -C "${engine_root}" remote add origin "${GZSELACO_REPOSITORY}"
git -C "${engine_root}" fetch -q --depth=1 origin "${GZSELACO_COMMIT}"
git -C "${engine_root}" checkout -q --detach FETCH_HEAD

resolved_commit="$(git -C "${engine_root}" rev-parse HEAD)"
if [[ "${resolved_commit}" != "${GZSELACO_COMMIT}" ]]; then
  echo "error: resolved GZSelaco commit does not match SOURCE_PIN.env" >&2
  exit 1
fi

python3 "${repo_root}/scripts/patch-gzselaco-ios-m0.py" \
  "${engine_root}" \
  "${repo_root}/overlays/gzselaco-ios/i_platform_stub.cpp"
python3 "${repo_root}/scripts/patch-gzselaco-vulkan-only-ios-m0.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-runtime-bootstrap-ios-m1.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-swapchain-ios-m2.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/run-m3-local-asset-patcher.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-engine-init-ios-m4.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-engine-renderer-ios-m4b.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-runtime-handoff-ios-m4b.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-title-menu-ios-m4b.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-zvulkan-engine-renderer-ios-m4b.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-title-menu-closure-ios-m4c.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-mach-class-registry-ios-m4d.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-zscript-diagnostics-ios-m4e.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-savegame-virtuals-ios-m4f.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-override-signature-diagnostics-ios-m4g.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-savegame-signatures-ios-m4h.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-savegame-api-diagnostics-ios-m4i.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-savegame-context-diagnostics-ios-m4j.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-savegame-compat-ios-m4k.py" \
  "${engine_root}"
python3 "${repo_root}/scripts/patch-gzselaco-savegame-receiver-diagnostics-ios-m4l.py" \
  "${engine_root}"

git -C "${engine_root}" diff --check

echo "materialized=${engine_root}"
echo "source_commit=${resolved_commit}"
echo "patch_level=M4L"
