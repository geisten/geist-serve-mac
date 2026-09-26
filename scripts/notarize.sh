#!/bin/sh
# Notarize a test build; publication and Sparkle appcast are separate actions.
set -eu
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set the Developer ID Application certificate fingerprint}"
: "${NOTARY_PROFILE:?Set the notarytool keychain profile name}"
: "${VERSION:?Set a numeric test version, e.g. 0.1.0}"
python3 -c 'import re,sys; assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+",sys.argv[1]), "numeric version required"' "$VERSION"
app=build/Geist.app
version_in_app=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
[ "$version_in_app" = "$VERSION" ] || { echo 'Build the app with the same VERSION first' >&2; exit 1; }
set --
if [ -n "${SIGNING_KEYCHAIN:-}" ]; then set -- --keychain "$SIGNING_KEYCHAIN"; fi
python3 scripts/distribution.py sign --app "$app" --identity "$SIGNING_IDENTITY" "$@"
mkdir -p build/notary
evidence=$(mktemp -d build/notary/run.XXXXXX)
ditto -c -k --keepParent "$app" "$evidence/Geist.zip"
python3 scripts/distribution.py notarize --artifact "$evidence/Geist.zip" --profile "$NOTARY_PROFILE" --log-dir "$evidence/app" "$@"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
VERSION="$VERSION" sh scripts/dmg.sh
dmg="build/Geist-$VERSION-arm64.dmg"
codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$@" "$dmg"
python3 scripts/distribution.py notarize --artifact "$dmg" --profile "$NOTARY_PROFILE" --log-dir "$evidence/dmg" "$@"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
spctl --assess --type execute --verbose=4 "$app"
python3 scripts/distribution.py verify --app "$app"
shasum -a 256 "$dmg" > "$dmg.sha256"
printf 'Notarization accepted and tickets verified. Evidence: %s\n' "$evidence"
