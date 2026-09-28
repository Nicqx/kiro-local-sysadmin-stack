#!/usr/bin/env bash
set -euo pipefail

SERVICE="kirocrew.service"
CONTAINER="kiro-local-ollama"

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Run this script as your normal login user, not with sudo." >&2
  exit 1
fi

echo "Stopping Kiro Local Sysadmin Stack and disabling automatic startup..."

if sudo systemctl cat "$SERVICE" >/dev/null 2>&1; then
  sudo systemctl disable --now "$SERVICE" >/dev/null
fi

if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  docker update --restart=no "$CONTAINER" >/dev/null
  docker stop "$CONTAINER" >/dev/null 2>&1 || true
fi

crew_active="$(systemctl is-active "$SERVICE" 2>/dev/null || true)"
crew_enabled="$(systemctl is-enabled "$SERVICE" 2>/dev/null || true)"
ollama_running="missing"
ollama_restart="missing"
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
  ollama_running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || true)"
  ollama_restart="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER" 2>/dev/null || true)"
fi

echo
echo "Kiro Crew:"
echo "  active:  ${crew_active:-unknown}"
echo "  enabled: ${crew_enabled:-unknown}"
echo "Ollama:"
echo "  running: ${ollama_running:-unknown}"
echo "  restart: ${ollama_restart:-unknown}"

if [[ "$crew_active" == "active" ]]; then
  echo "ERROR: Kiro Crew is still active." >&2
  exit 1
fi
if [[ "$crew_enabled" == "enabled" ]]; then
  echo "ERROR: Kiro Crew is still enabled for boot." >&2
  exit 1
fi
if [[ "$ollama_running" == "true" ]]; then
  echo "ERROR: Ollama container is still running." >&2
  exit 1
fi
if [[ "$ollama_restart" != "missing" && "$ollama_restart" != "no" ]]; then
  echo "ERROR: Ollama restart policy is '$ollama_restart', expected 'no'." >&2
  exit 1
fi

echo
echo "Stack stopped."
echo "It will stay stopped after reboot."
echo "Start it again with:"
echo "  ./start.sh"
