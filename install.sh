#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$ROOT/repo-lib.sh"

ensure_package_root
case "${1:-}" in
  --reset)
    shift
    "$PACKAGE_ROOT/scripts/full-reset-install.sh" "$@"
    ;;
  --fresh)
    shift
    "$PACKAGE_ROOT/scripts/fresh-install.sh" "$@"
    ;;
  "")
    "$PACKAGE_ROOT/scripts/install.sh"
    ;;
  *)
    echo "Usage: ./install.sh [--reset|--fresh]" >&2
    exit 2
    ;;
esac

"$ROOT/toolshim-fix.sh"

echo
echo "Installation complete. Verify grounded tool execution with:"
echo "  ./tool-smoke-test.sh"
