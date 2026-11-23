#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/katex"
if [[ -f "$DEST/katex.min.js" && -f "$DEST/auto-render.min.js" ]]; then exit 0; fi
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
VERSION='0.16.22'
echo "[MATE] Installing locally bundled KaTeX $VERSION"
curl --fail --location --silent --show-error --retry 3 "https://registry.npmjs.org/katex/-/katex-${VERSION}.tgz" -o "$TMP/katex.tgz"
tar -xzf "$TMP/katex.tgz" -C "$TMP"
cp "$TMP/package/dist/katex.min.js" "$DEST/"
cp "$TMP/package/dist/katex.min.css" "$DEST/"
cp "$TMP/package/dist/contrib/auto-render.min.js" "$DEST/"
cp -R "$TMP/package/dist/fonts" "$DEST/"
cp "$TMP/package/LICENSE" "$DEST/LICENSE_KaTeX.txt"
