#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Do not run the whole updater with sudo. Run ./update.sh as your normal login user." >&2
  exit 1
fi

echo "== Kiro Local Sysadmin Stack update =="

echo "[1/8] Updating repository..."
git pull --ff-only

# Older GitHub API-created helper files may have arrived without +x.
chmod +x "$ROOT/install.sh" "$ROOT/update.sh" "$ROOT/status.sh" "$ROOT/doctor.sh" "$ROOT/chat.sh" "$ROOT/token.sh" "$ROOT/uninstall.sh" "$ROOT/toolshim-fix.sh" "$ROOT/tool-smoke-test.sh" "$ROOT/acp-approval-smoke-test.sh" 2>/dev/null || true

# Do not silently downgrade an NVIDIA machine to CPU because the driver is temporarily unavailable.
NVIDIA_HOST=0
NVIDIA_SMI=""
if command -v lspci >/dev/null 2>&1 && lspci | grep -qi NVIDIA; then
  NVIDIA_HOST=1
  NVIDIA_SMI="$(command -v nvidia-smi 2>/dev/null || true)"
  [[ -z "$NVIDIA_SMI" && -x /usr/bin/nvidia-smi ]] && NVIDIA_SMI=/usr/bin/nvidia-smi
  if [[ -z "$NVIDIA_SMI" ]] || ! "$NVIDIA_SMI" -L >/dev/null 2>&1; then
    cat >&2 <<'EOF'

UPDATE ABORTED BEFORE SERVICES WERE STOPPED.
An NVIDIA PCI device is present, but nvidia-smi is unavailable or cannot talk
to the driver. Continuing would make the stack auto-detect CPU and could
replace a working GPU configuration with a CPU fallback.

Fix/restore the NVIDIA driver first, verify:
  nvidia-smi

Then run:
  ./update.sh
EOF
    exit 1
  fi
fi

source "$ROOT/repo-lib.sh"
ensure_package_root

CREW_WAS_ACTIVE=0
OLLAMA_WAS_RUNNING=0
if sudo systemctl is-active --quiet kirocrew.service 2>/dev/null; then CREW_WAS_ACTIVE=1; fi
if docker inspect -f '{{.State.Running}}' kiro-local-ollama 2>/dev/null | grep -qx true; then OLLAMA_WAS_RUNNING=1; fi

recover_on_failure() {
  local rc=$?
  trap - ERR
  echo >&2
  echo "Update failed (exit $rc). Attempting to restore previously running services..." >&2
  if (( OLLAMA_WAS_RUNNING )); then docker start kiro-local-ollama >/dev/null 2>&1 || true; fi
  if (( CREW_WAS_ACTIVE )); then
    sudo systemctl reset-failed kirocrew.service >/dev/null 2>&1 || true
    sudo systemctl start kirocrew.service >/dev/null 2>&1 || true
  fi
  exit "$rc"
}
trap recover_on_failure ERR

echo "[2/8] Stopping running stack services cleanly..."
if (( CREW_WAS_ACTIVE )); then sudo systemctl stop kirocrew.service; fi
if (( OLLAMA_WAS_RUNNING )); then docker stop kiro-local-ollama >/dev/null; fi

echo "[3/8] Updating Ollama runtime/image, Kiro Crew, Goose and stack configuration..."
bash "$PACKAGE_ROOT/scripts/update.sh" "$@"

echo "[4/8] Re-applying ToolShim, grounding and language guardrails..."
bash "$ROOT/toolshim-fix.sh"

echo "[5/8] Ensuring Ollama is running..."
if docker inspect kiro-local-ollama >/dev/null 2>&1; then
  docker start kiro-local-ollama >/dev/null 2>&1 || true
else
  echo "ERROR: kiro-local-ollama container does not exist after update." >&2
  exit 1
fi

OLLAMA_READY=0
for _ in $(seq 1 30); do
  if docker exec kiro-local-ollama ollama list >/dev/null 2>&1; then OLLAMA_READY=1; break; fi
  sleep 1
done
if (( ! OLLAMA_READY )); then
  echo "ERROR: Ollama did not become ready after update." >&2
  docker logs --tail 80 kiro-local-ollama >&2 || true
  exit 1
fi

if (( NVIDIA_HOST )); then
  GPU_WIRING="$(docker inspect kiro-local-ollama 2>/dev/null || true)"
  if ! grep -Eqi '"Driver"[[:space:]]*:[[:space:]]*"nvidia"|"Runtime"[[:space:]]*:[[:space:]]*"nvidia"|nvidia\.com/gpu|"gpu"' <<<"$GPU_WIRING"; then
    echo "ERROR: NVIDIA works on the host, but the updated Ollama container has no detectable GPU passthrough." >&2
    echo "Refusing to report a successful update with an accidental CPU-only Ollama configuration." >&2
    exit 1
  fi
fi

echo "[6/8] Updating all installed Ollama models..."
RUNTIME_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-local/runtime.env"
ACTIVE_MODEL=""
if [[ -f "$RUNTIME_ENV" ]]; then
  ACTIVE_MODEL="$(awk -F= '$1=="GOOSE_MODEL"{sub(/^[^=]*=/,""); print; exit}' "$RUNTIME_ENV")"
  [[ -z "$ACTIVE_MODEL" ]] && ACTIVE_MODEL="$(awk -F= '$1=="OLLAMA_MODEL"{sub(/^[^=]*=/,""); print; exit}' "$RUNTIME_ENV")"
fi

mapfile -t MODELS < <(
  {
    docker exec kiro-local-ollama ollama list 2>/dev/null | awk 'NR>1 && $1!="" {print $1}'
    [[ -n "$ACTIVE_MODEL" ]] && printf '%s\n' "$ACTIVE_MODEL"
  } | awk 'NF && !seen[$0]++'
)

if ((${#MODELS[@]} == 0)); then
  echo "No installed/configured Ollama models found to update."
else
  for model in "${MODELS[@]}"; do
    echo "  ollama pull $model"
    docker exec kiro-local-ollama ollama pull "$model"
  done
fi

echo "[7/8] Starting and health-checking Kiro Crew..."
sudo systemctl daemon-reload
sudo systemctl reset-failed kirocrew.service >/dev/null 2>&1 || true
if ! sudo systemctl is-active --quiet kirocrew.service; then sudo systemctl start kirocrew.service; fi

CREW_READY=0
for _ in $(seq 1 30); do
  if sudo systemctl is-active --quiet kirocrew.service; then CREW_READY=1; break; fi
  sleep 1
done
if (( ! CREW_READY )); then
  echo "ERROR: Kiro Crew service is not active after update." >&2
  sudo systemctl --no-pager --full status kirocrew.service >&2 || true
  sudo journalctl -u kirocrew.service -b -n 100 --no-pager >&2 || true
  exit 1
fi

CREW_PORT=5476
if [[ -f "$RUNTIME_ENV" ]]; then
  _p="$(awk -F= '$1=="KIROCREW_PORT"{print $2; exit}' "$RUNTIME_ENV")"
  [[ "$_p" =~ ^[0-9]+$ ]] && CREW_PORT="$_p"
fi

HTTP_CODE=000
for _ in $(seq 1 30); do
  HTTP_CODE="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${CREW_PORT}/" 2>/dev/null || true)"
  if [[ "$HTTP_CODE" != "000" && -n "$HTTP_CODE" ]]; then break; fi
  sleep 1
done
if [[ "$HTTP_CODE" == "000" || -z "$HTTP_CODE" ]]; then
  echo "ERROR: Kiro Crew service is active, but dashboard port ${CREW_PORT} is not reachable." >&2
  sudo journalctl -u kirocrew.service -b -n 100 --no-pager >&2 || true
  exit 1
fi

echo "[8/8] Final verification..."
CREW_BIN="$HOME/.local/share/kiro-local/runtime-home/.local/bin/kirocrew"
GOOSE_BIN="$HOME/.local/share/kiro-local/runtime-home/.local/bin/goose"
[[ -x "$CREW_BIN" ]] && "$CREW_BIN" --version || true
[[ -x "$GOOSE_BIN" ]] && "$GOOSE_BIN" --version || true
docker exec kiro-local-ollama ollama --version 2>/dev/null || true

if (( NVIDIA_HOST )) && [[ -n "$NVIDIA_SMI" ]]; then
  echo
  echo "NVIDIA:"
  "$NVIDIA_SMI" --query-gpu=name,driver_version,memory.total --format=csv,noheader 2>/dev/null || true
  echo "Ollama GPU wiring: detected"
fi

trap - ERR

echo
echo "Update complete."
echo "  Kiro Crew: active"
echo "  Dashboard: reachable on http://127.0.0.1:${CREW_PORT} (HTTP ${HTTP_CODE})"
echo "  Ollama:    running"
if ((${#MODELS[@]})); then printf '  Models:    %s\n' "${MODELS[*]}"; fi
echo
echo "Verification:"
echo "  ./tool-smoke-test.sh"
echo "  ./acp-approval-smoke-test.sh"
echo
echo "Fresh dashboard login URL:"
echo "  ./token.sh 8h"
