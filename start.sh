#!/usr/bin/env bash
set -euo pipefail

SERVICE="kirocrew.service"
CONTAINER="kiro-local-ollama"
RUNTIME_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/kiro-local/runtime.env"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as your normal login user, not with sudo." >&2
  exit 1
fi

# Refuse to start an NVIDIA-configured stack if the host GPU driver is broken.
if command -v lspci >/dev/null 2>&1 && lspci | grep -qi NVIDIA; then
  NVIDIA_SMI="$(command -v nvidia-smi 2>/dev/null || true)"
  [[ -z "$NVIDIA_SMI" && -x /usr/bin/nvidia-smi ]] && NVIDIA_SMI=/usr/bin/nvidia-smi
  if [[ -z "$NVIDIA_SMI" ]] || ! "$NVIDIA_SMI" -L >/dev/null 2>&1; then
    echo "ERROR: NVIDIA GPU detected, but nvidia-smi is not healthy." >&2
    echo "Fix/reboot the NVIDIA driver first, then run ./start.sh again." >&2
    exit 1
  fi
fi

echo "Starting Kiro Local Sysadmin Stack and enabling automatic startup..."

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "ERROR: Ollama container '$CONTAINER' does not exist." >&2
  echo "Run ./update.sh or ./install.sh first." >&2
  exit 1
fi

docker update --restart=unless-stopped "$CONTAINER" >/dev/null
docker start "$CONTAINER" >/dev/null 2>&1 || true

OLLAMA_READY=0
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER" ollama list >/dev/null 2>&1; then
    OLLAMA_READY=1
    break
  fi
  sleep 1
done
if (( ! OLLAMA_READY )); then
  echo "ERROR: Ollama did not become ready." >&2
  docker logs --tail 80 "$CONTAINER" >&2 || true
  exit 1
fi

sudo systemctl daemon-reload
sudo systemctl reset-failed "$SERVICE" >/dev/null 2>&1 || true
sudo systemctl enable --now "$SERVICE" >/dev/null

CREW_READY=0
for _ in $(seq 1 30); do
  if sudo systemctl is-active --quiet "$SERVICE"; then
    CREW_READY=1
    break
  fi
  sleep 1
done
if (( ! CREW_READY )); then
  echo "ERROR: Kiro Crew did not become active." >&2
  sudo systemctl --no-pager --full status "$SERVICE" >&2 || true
  sudo journalctl -u "$SERVICE" -b -n 100 --no-pager >&2 || true
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
  if [[ "$HTTP_CODE" != "000" && -n "$HTTP_CODE" ]]; then
    break
  fi
  sleep 1
done
if [[ "$HTTP_CODE" == "000" || -z "$HTTP_CODE" ]]; then
  echo "ERROR: Kiro Crew service is active, but dashboard port ${CREW_PORT} is not reachable." >&2
  sudo journalctl -u "$SERVICE" -b -n 100 --no-pager >&2 || true
  exit 1
fi

echo
echo "Stack started."
echo "  Kiro Crew: active + enabled at boot"
echo "  Dashboard: http://127.0.0.1:${CREW_PORT} (HTTP ${HTTP_CODE})"
echo "  Ollama: running + restart=unless-stopped"
echo
echo "To free the machine resources again:"
echo "  ./stop.sh"
