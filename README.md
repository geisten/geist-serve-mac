# Geist for macOS

**Runs here. Stays here.** A menu bar launcher for a local text workspace.
Download a suggested model once, then try rewriting, summarizing and ideas
on your Mac. No account, no saved prompt history, and no prompts sent to a
cloud service.

Apple Silicon, macOS 14+. This is a development preview. Local builds are
ad-hoc signed; public distribution needs Developer ID signing and
notarization. No app release or Homebrew cask has been published by this change.

## One application, two platforms

Model selection, hardware assessment, downloads, SHA-256 verification,
memory policy and inference supervision live in the C23 `geist-app` in
[geist-serve](https://github.com/geisten/geist-serve). The app owns a private geistd Unix-socket child. Its embedded web
interface is shared with the Raspberry Pi package. The inference engine
geistlib remains unchanged.

This repository contains only the native shell: menu bar, opening the local
browser, Start at Login, manual update checking and stopping its own child
runtime when the app quits. Model policy is not duplicated in Swift.
The app does not stop Ollama or install a global command-line tool.

The first screen shows RAM, compute cores and free disk space, then
recommended, conditional or unavailable models with reasons. Completed local
runs add measured generation speed. Hardware estimates are labelled separately
from measurements. Slow models remain selectable.

See the shared [app guide](https://github.com/geisten/geist-serve/blob/main/docs/APP.md)
for the catalog, model licenses, memory assumptions, privacy boundary and
Pi desktop/SSH setup. Until the companion change is merged, that guide is
in the local runtime checkout at `docs/APP.md`.

## Build a local app and DMG

Use the companion geist-serve checkout containing `App.mk`:

```sh
make RUNTIME_DIR=../geist-serve
make test RUNTIME_DIR=../geist-serve
make dmg RUNTIME_DIR=../geist-serve VERSION=0.0.0-dev
make run RUNTIME_DIR=../geist-serve
```

The build produces `build/Geist.app` and `build/Geist-0.0.0-dev-arm64.dmg`.
It builds the C23 runtime and the pinned inference engine with static
OpenMP, and rejects Homebrew runtime-library dependencies. The downloaded
model is not included. A verified prebuilt pair can instead be supplied in
`GEIST_RUNTIME_BIN_DIR`; it must contain executable `geist-app` and
`geistd` files for Apple Silicon.

SwiftPM resolves Sparkle using Package.resolved. Automatic update checks are
off; the menu retains manual checks against the configured release feed.
The native runtime test uses an isolated temporary data directory and asks
only its own instance to quit. It does not close another installed copy.

The two-repository integration requires the C23 runtime change first.
CI compiles the Swift shell and builds/tests the pair on each pull request.
`geist-serve.ref` pins its companion source. Manual runs can explicitly test
another full commit SHA. Publish the pinned runtime commit before dependent
CI runs; pin a merged revision before preparing a public Mac release.

## Data and migration

Models stay in `~/Library/Application Support/Geist/models`. Catalog files
from the previous app are reused after verification. Choose Use once to
select a previous model; the old Swift selected-model preference is not
migrated. The former LAN toggle and CLI installer are no longer in this
shell. A headless Pi is reached through an SSH tunnel to its loopback UI.

For isolated developer tests, set `GEIST_HOME` to a temporary directory.
`GEIST_MODEL=/path/to/file.gguf` forwards an explicit custom model to the
runtime; this bypasses catalog validation. `GEIST_NO_OPEN=1` suppresses
browser opening, and `GEIST_TEST_QUIT=1` exercises native application quit.

Apache-2.0. Model weights retain their own licenses.
