#!/usr/bin/env bash
set -euo pipefail

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-local"
RUNTIME_ENV="$CONFIG_ROOT/runtime.env"
[[ -f "$RUNTIME_ENV" ]] || { echo "Missing $RUNTIME_ENV. Install the stack first." >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "$RUNTIME_ENV"
set +a

GOOSE_BIN="${GOOSE_BIN:-${XDG_DATA_HOME:-$HOME/.local/share}/kiro-local/runtime-home/.local/bin/goose}"
[[ -x "$GOOSE_BIN" ]] || { echo "Goose not found: $GOOSE_BIN" >&2; exit 1; }

probe="$(mktemp "${TMPDIR:-/tmp}/kiro-goose-tool-test.XXXXXX")"
trap 'rm -f "$probe"' EXIT
nonce="KIRO_TOOL_OK_$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
printf '%s\n' "$nonce" > "$probe"
chmod 600 "$probe"

export GOOSE_MODE=auto
export GOOSE_TOOLSHIM=1
export GOOSE_TOOLSHIM_OLLAMA_MODEL="${GOOSE_TOOLSHIM_OLLAMA_MODEL:-${GOOSE_MODEL:-qwen3:8b}}"

prompt="Use the available developer/shell tool to read the file $probe. Return the exact file contents. Do not guess, infer, simulate, or fabricate the value."

echo "Running grounded Goose tool-use test..."
echo "  model: ${GOOSE_MODEL:-unknown}"
echo "  toolshim interpreter: $GOOSE_TOOLSHIM_OLLAMA_MODEL"
echo

set +e
out="$($GOOSE_BIN run --no-session --max-turns 6 --text "$prompt" 2>&1)"
rc=$?
set -e
printf '%s\n' "$out"
echo

if [[ $rc -ne 0 ]]; then
  echo "TOOL TEST FAILED: goose exited with status $rc" >&2
  exit "$rc"
fi

if grep -Fq "$nonce" <<<"$out"; then
  echo "TOOL TEST PASSED"
  echo "Goose returned a random value that existed only inside the temporary file, so a real tool read occurred."
  exit 0
fi

echo "TOOL TEST FAILED" >&2
echo "The unknown nonce was not returned, so this run did not prove real tool execution." >&2
exit 2
