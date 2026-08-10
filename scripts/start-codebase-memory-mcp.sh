#!/usr/bin/env bash
set -Eeuo pipefail

repo_root="$(git -C "$(dirname "$0")/.." rev-parse --show-toplevel)"
project_binary="${repo_root}/.codebase-memory/bin/codebase-memory-mcp"

if [[ -n "${SELACOIOS_CODEBASE_MEMORY_BIN:-}" ]]; then
  server_binary="${SELACOIOS_CODEBASE_MEMORY_BIN}"
elif [[ -x "${project_binary}" ]]; then
  server_binary="${project_binary}"
elif server_binary="$(command -v codebase-memory-mcp)"; then
  :
else
  echo "error: Codebase Memory MCP binary is not available" >&2
  echo "expected project-local binary: ${project_binary}" >&2
  exit 127
fi

export CBM_CACHE_DIR="${CBM_CACHE_DIR:-${repo_root}/.codebase-memory/cache}"
export CBM_LOG_LEVEL="${CBM_LOG_LEVEL:-warn}"

exec "${server_binary}" "$@"
