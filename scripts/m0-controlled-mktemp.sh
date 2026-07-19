#!/usr/bin/env bash
set -euo pipefail

real_mktemp="${SELACOIOS_REAL_MKTEMP:?}"
controlled_root="${SELACOIOS_CONTROLLED_TMP_ROOT:?}"

if [[ "$#" -eq 1 && "$1" == "-d" ]]; then
  mkdir -p "${controlled_root}"
  exec "${real_mktemp}" -d "${controlled_root}/tmp.XXXXXX"
fi

exec "${real_mktemp}" "$@"
