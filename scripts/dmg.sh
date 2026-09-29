#!/bin/sh
# Local review image. Distribution signing/notarization is a separate step.
set -eu
cd "$(dirname "$0")/.."
version=${VERSION:-0.0.0-dev}
case "$version" in *[!A-Za-z0-9._-]*) echo 'Invalid version' >&2; exit 1;; esac
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT HUP INT TERM
ditto build/Geist.app "$stage/Geist.app"
ln -s /Applications "$stage/Applications"
hdiutil create -volname Geist -srcfolder "$stage" -format UDZO -ov "build/Geist-$version-arm64.dmg"
