#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"

repo_version() {
  [[ -f "$VERSION_FILE" ]] || { echo "VERSION file is missing." >&2; return 1; }
  tr -d '[:space:]' < "$VERSION_FILE"
}

ensure_package_root() {
  # Future-proofing: if the repository is fully flattened later, prefer it.
  if [[ -x "$REPO_ROOT/scripts/install.sh" ]]; then
    PACKAGE_ROOT="$REPO_ROOT"
    export PACKAGE_ROOT
    return 0
  fi

  command -v unzip >/dev/null 2>&1 || {
    echo "Missing prerequisite: unzip" >&2
    echo "Install it first (Ubuntu/Debian: sudo apt install unzip)." >&2
    return 1
  }

  local version zip package_dir
  version="$(repo_version)"
  zip="$REPO_ROOT/kiro-local-sysadmin-stack-v${version}.zip"
  package_dir="$REPO_ROOT/.package/kiro-local-sysadmin-stack-v${version}"

  if [[ ! -x "$package_dir/scripts/install.sh" ]]; then
    echo "Preparing repository package v${version}..."
    rm -rf "$REPO_ROOT/.package"
    mkdir -p "$REPO_ROOT/.package"

    if [[ ! -f "$zip" ]]; then
      [[ -x "$REPO_ROOT/bootstrap.sh" || -f "$REPO_ROOT/bootstrap.sh" ]] || {
        echo "Neither a direct source tree nor bootstrap package data is available." >&2
        return 1
      }
      bash "$REPO_ROOT/bootstrap.sh"
    fi

    unzip -q -o "$zip" -d "$REPO_ROOT/.package"
  fi

  [[ -x "$package_dir/scripts/install.sh" ]] || {
    echo "Prepared package is incomplete: $package_dir" >&2
    return 1
  }

  PACKAGE_ROOT="$package_dir"
  export PACKAGE_ROOT
}

delegate_script() {
  local script="$1"; shift
  ensure_package_root
  [[ -x "$PACKAGE_ROOT/scripts/$script" ]] || {
    echo "Script not found in package: scripts/$script" >&2
    return 1
  }
  exec "$PACKAGE_ROOT/scripts/$script" "$@"
}
