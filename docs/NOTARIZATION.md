# Developer ID test distribution

The distribution build is separate from the ad-hoc development build. It does
not create a tag, a GitHub release or a Sparkle update. An accepted Apple
submission is necessary; local signing tests cannot establish notarization.

## Local keychain

Import your Developer ID Application certificate **with its private key** into
Keychain Access. Keep the original export private. Run `security find-identity
-v -p codesigning` locally to obtain the certificate fingerprint. Configure a
notarytool keychain profile using Apple's interactive `xcrun notarytool
store-credentials` flow. Do not put passwords or private keys in chat, source,
shell history or issue bodies. Only the fingerprint and profile name are needed
by the build.

```sh
make VERSION=0.1.0
SIGNING_IDENTITY='<certificate fingerprint>' NOTARY_PROFILE='geist-notary' \
  VERSION=0.1.0 sh scripts/notarize.sh
```

Optional `SIGNING_KEYCHAIN` selects a separate keychain. The process signs
nested Sparkle helpers and runtimes before the outer app, using secure
timestamps and Hardened Runtime. It preserves helper entitlements. It records
the final signed runtime hashes before sealing the app. It notarizes and
staples the app, builds/signs/notarizes/staples the DMG, verifies tickets and
Gatekeeper assessments, and finally hashes the unchanged DMG.

Apple submission JSON and logs are saved in a unique `build/notary/run.*`
directory. A rejected or unfinished submission fails the command. No unsigned
fallback is published. Interrupted submissions must be checked using their
Apple submission ID before retrying. An independent clean Mac should also test
the quarantined DMG and offline launch; local assessments alone do not prove
that installation experience.

## GitHub test workflow

The manually dispatched `notarize` workflow requires the `notarization`
environment and these secrets (values must be entered in GitHub Settings):

- `MACOS_CERT_P12`: base64 Developer ID Application certificate/private-key export.
- `MACOS_CERT_PASSWORD`: export password.
- `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`: team notary API identifiers.
- `APPSTORE_API_KEY`: base64 contents of the matching `.p8` private key.

The workflow uses a temporary keychain, deletes credentials on every exit and
uploads only the accepted DMG, checksum and Apple logs. Protect the environment
so only reviewed source can access the credentials. Appcast signing and public
distribution are deliberately separate from this test workflow.

GitHub exposes manual dispatch only after the workflow exists on the default
branch. While this change is a draft PR, use the local keychain path. Merely
adding the secrets does not register the workflow or authorize merging it.

References: [Apple signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/),
[Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).
