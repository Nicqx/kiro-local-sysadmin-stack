#!/usr/bin/env bash
set -euo pipefail

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not run this whole script with sudo. Run it as your normal login user." >&2
  exit 1
fi

CONFIG_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-local"
RUNTIME_ENV="$CONFIG_ROOT/runtime.env"
GUARDRAILS="$CONFIG_ROOT/sysadmin-guardrails.md"
DROPIN_DIR="/etc/systemd/system/kirocrew.service.d"
DROPIN="$DROPIN_DIR/30-local-toolshim.conf"

[[ -f "$RUNTIME_ENV" ]] || {
  echo "Missing $RUNTIME_ENV. Install the stack first with ./install.sh" >&2
  exit 1
}

set -a
# shellcheck disable=SC1090
source "$RUNTIME_ENV"
set +a

MODEL="${GOOSE_MODEL:-${OLLAMA_MODEL:-qwen3:8b}}"
WORKSPACE="${KIROCREW_WORKSPACE:-${XDG_DATA_HOME:-$HOME/.local/share}/kiro-local/workspace}"

# Persist for terminal wrappers as well as the managed systemd gateway.
tmp="$(mktemp)"
grep -v '^GOOSE_TOOLSHIM=' "$RUNTIME_ENV" | grep -v '^GOOSE_TOOLSHIM_OLLAMA_MODEL=' > "$tmp" || true
printf 'GOOSE_TOOLSHIM=1\nGOOSE_TOOLSHIM_OLLAMA_MODEL=%s\n' "$MODEL" >> "$tmp"
cat "$tmp" > "$RUNTIME_ENV"
rm -f "$tmp"
chmod 600 "$RUNTIME_ENV"

mkdir -p "$CONFIG_ROOT" "$WORKSPACE"
touch "$GUARDRAILS"
if ! grep -Fq 'Tool-execution grounding rules:' "$GUARDRAILS"; then
  cat >> "$GUARDRAILS" <<'EOF'

Tool-execution grounding rules:
11. A command is NOT executed merely because you described it, planned it, or printed it. Use the actual developer/shell tool.
12. Never invent, simulate, predict, or reconstruct command output. Only report output that came back from a real tool result in this session.
13. If the user asks you to inspect the machine, you MUST call an appropriate tool before answering factual machine-state questions. If no tool call succeeds, explicitly say that you could not inspect the machine.
14. Do not say that you executed a command, received command output, completed a check, or obtained a result unless a corresponding successful tool result exists in the current turn.
15. For read-only inspection requests, prefer a small number of direct commands and report their actual stdout/stderr.
EOF
fi
cp "$GUARDRAILS" "$WORKSPACE/.goosehints"

sudo mkdir -p "$DROPIN_DIR"
sudo tee "$DROPIN" >/dev/null <<EOF
[Service]
Environment="GOOSE_TOOLSHIM=1"
Environment="GOOSE_TOOLSHIM_OLLAMA_MODEL=$MODEL"
EOF
sudo systemctl daemon-reload

if sudo systemctl cat kirocrew.service >/dev/null 2>&1; then
  sudo systemctl reset-failed kirocrew.service >/dev/null 2>&1 || true
  sudo systemctl restart kirocrew.service
fi

echo "Goose ToolShim enabled with interpreter model: $MODEL"
echo "Grounded tool-output guardrails installed."
echo "Next: ./tool-smoke-test.sh"
