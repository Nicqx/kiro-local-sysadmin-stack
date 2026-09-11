#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
git pull --ff-only
source "$ROOT/repo-lib.sh"
ensure_package_root
"$PACKAGE_ROOT/scripts/update.sh" "$@"
"$ROOT/toolshim-fix.sh"
