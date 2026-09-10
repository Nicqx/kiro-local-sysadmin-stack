#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/repo-lib.sh"
case "${1:-}" in
  --reset)
    shift
    delegate_script full-reset-install.sh "$@"
    ;;
  --fresh)
    shift
    delegate_script fresh-install.sh "$@"
    ;;
  "")
    delegate_script install.sh
    ;;
  *)
    echo "Usage: ./install.sh [--reset|--fresh]" >&2
    exit 2
    ;;
esac
