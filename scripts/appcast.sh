#!/bin/sh
# appcast.sh <dist-dir> — sign the DMG(s) in dist/ and write dist/appcast.xml.
# The private key comes from SPARKLE_PRIVATE_KEY (the repo secret); the
# release workflow calls this after building the DMG.
set -eu
cd "$(dirname "$0")/.."
DIST=${1:?usage: appcast.sh <dist-dir>}
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is not set}"
BIN=.build/artifacts/sparkle/Sparkle/bin
KEY=$(mktemp); trap 'rm -f "$KEY"' EXIT
printf '%s' "$SPARKLE_PRIVATE_KEY" > "$KEY"
"$BIN/generate_appcast" --ed-key-file "$KEY" \
    --download-url-prefix "https://github.com/geisten/geist-serve-mac/releases/latest/download/" "$DIST"
echo "wrote $DIST/appcast.xml"
