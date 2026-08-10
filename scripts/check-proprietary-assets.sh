#!/usr/bin/env bash
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: run this check from a Git worktree" >&2
  exit 2
fi

# This check intentionally evaluates tracked paths rather than file contents.
# Documentation may name Selaco.ipk3 while the archive itself remains forbidden.
forbidden_regex='(^|/)(selaco[^/]*\.(ipk3|pk3|wad)|[^/]*\.(ipa|xcarchive|mobileprovision|p12))$'
mapfile -t forbidden_paths < <(git ls-files | grep -E -i "${forbidden_regex}" || true)

if ((${#forbidden_paths[@]} > 0)); then
  echo "error: forbidden proprietary data or signing/build output is tracked:" >&2
  printf '  - %s\n' "${forbidden_paths[@]}" >&2
  echo "Remove these paths from Git history before continuing." >&2
  exit 1
fi

# Catch the canonical commercial archive even if someone gives it an unexpected path.
if find . -path './.git' -prune -o -type f -iname 'Selaco.ipk3' -print -quit | grep -q .; then
  echo "error: a local Selaco.ipk3 archive exists inside the repository tree" >&2
  echo "Keep purchased game data outside the checkout and import it only at runtime." >&2
  exit 1
fi

echo "asset-boundary: PASS"
