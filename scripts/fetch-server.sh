#!/bin/sh
# fetch-server.sh — the geist-serve binary this app bundles, from its
# pinned release, SHA-256 verified. Bumping the pin means changing both
# lines below; the checksum comes from that release's SHA256SUMS.
set -eu
SERVE_VERSION=v0.1.0
SERVE_SHA256=5c2396a7293fedb3e6ba34e937f224806d6eeb86e079e2fe0a342b56c147d406
ASSET=geist-serve-macos-arm64
OUT=${1:-build/geist-serve}

mkdir -p "$(dirname "$OUT")"
if [ -f "$OUT" ] && [ "$(shasum -a 256 "$OUT" | cut -d' ' -f1)" = "$SERVE_SHA256" ]; then
    exit 0
fi
echo "fetching geist-serve $SERVE_VERSION ..."
curl -fsSL --retry 3 -o "$OUT.tmp" \
    "https://github.com/geisten/geist-serve/releases/download/$SERVE_VERSION/$ASSET"
have=$(shasum -a 256 "$OUT.tmp" | cut -d' ' -f1)
[ "$have" = "$SERVE_SHA256" ] || { echo "geist-serve: checksum mismatch ($have)" >&2; rm -f "$OUT.tmp"; exit 1; }
chmod 0755 "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
echo "geist-serve $SERVE_VERSION ok"
