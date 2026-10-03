#!/bin/sh
# Local review image. Distribution signing/notarization is a separate step.
set -eu
cd "$(dirname "$0")/.."
version=${VERSION:-0.0.0-dev}
case "$version" in *[!A-Za-z0-9._-]*) echo 'Invalid version' >&2; exit 1;; esac
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
ditto build/geisten.app "$stage/geisten.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname geisten -srcfolder "$stage" -format UDZO -ov "build/geisten-$version-arm64.dmg"
