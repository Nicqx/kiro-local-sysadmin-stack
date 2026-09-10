#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/repo-lib.sh"
delegate_script doctor.sh "$@"
