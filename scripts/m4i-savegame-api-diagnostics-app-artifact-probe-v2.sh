#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git rev-parse --show-toplevel)"
source_probe="${repo_root}/scripts/m4i-savegame-api-diagnostics-app-artifact-probe.sh"

if [[ ! -f "${source_probe}" ]]; then
  echo "error: M4I predecessor wrapper is missing: ${source_probe}" >&2
  exit 2
fi

workdir="$(mktemp -d)"
cleanup() {
  rm -rf "${workdir}"
}
trap cleanup EXIT

patched_probe="${workdir}/m4i-savegame-api-diagnostics-app-artifact-probe.sh"
python3 - "${source_probe}" "${patched_probe}" <<'PY'
from __future__ import annotations

import pathlib
import sys

source = pathlib.Path(sys.argv[1])
destination = pathlib.Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

old = '''if text.count(compile_old) != 1:
    raise SystemExit("M4I title-menu compile-probe marker changed")
text = text.replace(compile_old, compile_new, 1)
'''
new = '''if text.count(compile_old) != 2:
    raise SystemExit("M4I title-menu compile-probe marker changed")
text = text.replace(compile_old, compile_new)
'''
if text.count(old) != 1:
    raise SystemExit("M4I wrapper compile-marker validator changed")
text = text.replace(old, new, 1)

destination.write_text(text, encoding="utf-8")
destination.chmod(0o755)
PY

bash -n "${patched_probe}"
bash "${patched_probe}"
