#!/usr/bin/env bash
# Stage the npm package from a built sdist, so npm ships exactly the PyPI bundle.
# Usage: packaging/npm/stage.sh dist/memory_bank_skill-X.Y.Z.tar.gz <new-out-dir>
# Then:  npm publish <out-dir> --access public
set -euo pipefail

sdist="${1:?sdist path required}"
out="${2:?output dir required}"
here="$(cd "$(dirname "$0")" && pwd -P)"

if [ -e "$out" ]; then
  echo "stage.sh: $out already exists; pass a new directory" >&2
  exit 1
fi
mkdir -p "$out/bin"
tar -xzf "$sdist" -C "$out" --strip-components=1
cp "$here/package.json" "$out/package.json"
cp "$here/memory-bank.js" "$out/bin/memory-bank.js"
chmod +x "$out/bin/memory-bank.js"
version="$(tr -d '[:space:]' < "$out/VERSION")"
(cd "$out" && npm pkg set "version=$version")
