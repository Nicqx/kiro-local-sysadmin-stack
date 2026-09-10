#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION="0.3.5"
BUNDLE="$ROOT/bundle/v${VERSION}"
OUT="$ROOT/kiro-local-sysadmin-stack-v${VERSION}.zip"
EXPECTED="e3cb9343e626b2cdf82a5a1e06552e5b4edec19dd916c4b2d13403b0611954e5"

command -v base64 >/dev/null || { echo "Missing prerequisite: base64" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "Missing prerequisite: sha256sum" >&2; exit 1; }

# part-07.b64 is an obsolete intermediate upload. Use the verified split 07a/07b/07c parts instead.
PARTS=(
  part-00.b64 part-01.b64 part-02.b64 part-03.b64
  part-04.b64 part-05.b64 part-06.b64
  part-07a.b64 part-07b.b64 part-07c.b64 part-08.b64
)

for part in "${PARTS[@]}"; do
  [[ -f "$BUNDLE/$part" ]] || { echo "Missing bundle part: $part" >&2; exit 1; }
done

{
  for part in "${PARTS[@]}"; do
    cat "$BUNDLE/$part"
  done
} | tr -d '\r\n' | base64 -d > "$OUT"

ACTUAL="$(sha256sum "$OUT" | awk '{print $1}')"
if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "Checksum mismatch: expected $EXPECTED, got $ACTUAL" >&2
  rm -f "$OUT"
  exit 1
fi

echo "Created and verified: $OUT"
echo "SHA-256: $ACTUAL"
echo
echo "Next:"
echo "  unzip kiro-local-sysadmin-stack-v${VERSION}.zip"
echo "  cd kiro-local-sysadmin-stack-v${VERSION}"
echo "  ./scripts/install.sh"
echo
echo "For a complete test reset instead of a normal install:"
echo "  ./scripts/full-reset-install.sh"
