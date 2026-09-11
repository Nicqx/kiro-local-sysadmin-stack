#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-local/runtime.env"

[[ -f "$RUNTIME_ENV" ]] || {
  echo "Missing $RUNTIME_ENV. Install the stack first." >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source "$RUNTIME_ENV"
set +a

export GOOSE_MODE=approve
export GOOSE_TOOLSHIM=1
export GOOSE_TOOLSHIM_OLLAMA_MODEL="${GOOSE_TOOLSHIM_OLLAMA_MODEL:-${GOOSE_MODEL:-qwen3:8b}}"

exec python3 "$ROOT/acp-approval-smoke-test.py"
