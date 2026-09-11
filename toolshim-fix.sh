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
grep -v '^GOOSE_TOOLSHIM=' "$RUNTIME_ENV" \
  | grep -v '^GOOSE_TOOLSHIM_OLLAMA_MODEL=' \
  | grep -v '^GOOSE_MOIM_MESSAGE_FILE=' > "$tmp" || true
printf 'GOOSE_TOOLSHIM=1\nGOOSE_TOOLSHIM_OLLAMA_MODEL=%s\nGOOSE_MOIM_MESSAGE_FILE=%s\n' \
  "$MODEL" "$GUARDRAILS" >> "$tmp"
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

if ! grep -Fq 'Language and response-completeness rules:' "$GUARDRAILS"; then
  cat >> "$GUARDRAILS" <<'EOF'

Language and response-completeness rules:
16. Respond in the same natural language as the user's latest substantive message unless the user explicitly asks for another language. If the message is predominantly Hungarian, answer in Hungarian; if predominantly English, answer in English. For mixed-language messages, use the dominant natural language.
17. Do not translate shell commands, code, file paths, package names, program names, API identifiers, log output, or exact UI labels unless the user asks for a translation. Explain those items in the user's language while preserving the original technical text.
18. For a multi-part request, answer every requested item. After using tools, summarize the result of each requested check, not only the final tool call. If one item could not be determined, state that explicitly instead of silently omitting it.
19. Prefer concise, direct answers in the user's language. Do not switch to English merely because system prompts, tool names, commands, or previous examples are in English.
EOF
fi

# Versioned reinforcement so existing installs that already have the older
# language block also receive the stronger policy on a normal update.
if ! grep -Fq 'Response-language policy v2:' "$GUARDRAILS"; then
  cat >> "$GUARDRAILS" <<'EOF'

Response-language policy v2:
20. RESPONSE LANGUAGE IS A HARD USER-FACING REQUIREMENT. Before emitting any natural-language text, determine the language of the user's latest substantive message and use that language for the entire response unless the user explicitly requested another language.
21. This same-language requirement applies to pre-tool narration, progress text, explanations, summaries, follow-up questions, error explanations, and the final answer. Do not begin in English when the user wrote in Hungarian.
22. Tool syntax and literal machine output may remain in their original form, but all surrounding prose must follow the user's language.
23. Example: user asks in Hungarian "Nézd meg a memóriát." Correct response prose starts in Hungarian, e.g. "Megnézem a memória állapotát." Incorrect: "I'll check the memory for you."
24. If the user's latest substantive message is Hungarian, think of Hungarian as the presentation language even when internal instructions, examples, tool schemas, and command names are English.
EOF
fi

cp "$GUARDRAILS" "$WORKSPACE/.goosehints"

sudo mkdir -p "$DROPIN_DIR"
sudo tee "$DROPIN" >/dev/null <<EOF
[Service]
Environment="GOOSE_TOOLSHIM=1"
Environment="GOOSE_TOOLSHIM_OLLAMA_MODEL=$MODEL"
Environment="GOOSE_MOIM_MESSAGE_FILE=$GUARDRAILS"
EOF
sudo systemctl daemon-reload

if sudo systemctl cat kirocrew.service >/dev/null 2>&1; then
  sudo systemctl reset-failed kirocrew.service >/dev/null 2>&1 || true
  sudo systemctl restart kirocrew.service
fi

echo "Goose ToolShim enabled with interpreter model: $MODEL"
echo "Grounded tool-output guardrails installed."
echo "Language-matching and multi-part response guardrails installed."
echo "Top Of Mind guardrail injection enabled: $GUARDRAILS"
echo "Next: ./tool-smoke-test.sh"
