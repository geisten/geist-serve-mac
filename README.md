# Geist for macOS

**Runs here. Stays here.** A desktop model manager for one shared local model service.
Download a suggested model once, then connect the terminal, Continue in VS Code
or OpenCode through the same geistd. The current gateway supports text chat;
agent tools are explicitly unsupported. Geist sends no prompts to a cloud
service; connected editors have their own storage and telemetry settings.

Apple Silicon, macOS 14+. This is a development preview. Local builds are
ad-hoc signed; public distribution needs Developer ID signing and
notarization. No app release or Homebrew cask has been published by this change.

## One application, two platforms

Model selection, hardware assessment, downloads, SHA-256 verification,
memory policy and inference supervision live in the C23 `geist-app` in
[geist-serve](https://github.com/geisten/geist-serve). The app owns a private geistd Unix-socket child. Its embedded web
interface is shared with the Raspberry Pi package. The inference engine
geistlib remains unchanged.

This repository contains the native desktop host: an AppKit window with an
ephemeral WKWebView, a Dock icon, menu bar controls, Start at Login and manual
update checking. The normal launch does not open a browser. Closing the window
or quitting the desktop app leaves
the shared service running for other clients. Use Stop model service to stop
it explicitly. Sparkle waits for the service to stop before installing an update.
If stopping fails, installation is cancelled and the menu explains the failure.
The stop runs off the UI thread; a cancelled update cannot resume an old installer.
Model policy is not duplicated in Swift. The bundled terminal client lives at
`Geist.app/Contents/MacOS/geist-cli`; no global command is installed automatically.

The first screen shows the catalog with a platform-checked suggestion and a
concise preview notice. Clicking a model name or download icon downloads and
starts it; clicking an installed model starts it directly. Progress, pause and
resume stay in the same row. There is no separate setup/start button. A smaller
fallback is considered by the shared service. **Models** keeps the catalog and **Quick test** in one view: side by side
in the default window, stacked in a narrow one, with independent scrolling.
**Connect a program** opens editor setup. Each catalog row has a download ring:
empty, percentage, paused, checking, or closed green with a check for downloaded.
The running state and hardware suitability are separate. The metric row below the
active model expands to show machine details and measurements in the same place. **Settings** holds language and service
controls. The gear opens settings directly. The interface follows the OS language
(German, otherwise English) until an explicit language is selected. **System language**
restores automatic detection. This preference also updates native menu labels and
survives reconnects; it does not translate existing input or model responses.
The white interface uses labeled icons for common actions and keeps model speed,
RAM and file size beside the active model. The native menu shows the active model and status and offers direct
**Models** and **Connect a program** routes without reloading.

**Quick test** is optional. Enter sends, Shift + Enter inserts a newline, and
follow-ups use this window's conversation. Explicit model choices, answer language
and per-model preview consent persist. The test lives only in page memory and
is cleared by Clear test, reloading or quitting.
Hardware suitability does not establish answer quality.

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
model is not included. A verified prebuilt runtime can instead be supplied in
`GEIST_RUNTIME_BIN_DIR`; it must contain executable `geist`, `geist-app` and
`geistd` files for Apple Silicon. The bundle renames `geist` to `geist-cli` to
avoid colliding with `Geist` on case-insensitive filesystems.

SwiftPM resolves Sparkle using Package.resolved. Automatic update checks run daily; the menu also offers manual checks against the configured release feed.
The native runtime test uses an isolated temporary data directory and asks
its own app instances to quit and reattach, verifies that the same service
survives, then explicitly stops that isolated test service.

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
window opening, and `GEIST_TEST_QUIT=1` exercises native application quit.

Apache-2.0. Model weights retain their own licenses.

## Desktop UI verification

`make test` also exercises the real shared UI in WKWebView, including task
loading, DE/EN switching without losing input, small-window layout, a private
write-only test clipboard and close/reopen without stopping the service. Set
`GEIST_TEST_MODEL` to the verified SmolLM2 360M catalog GGUF to additionally
select the model, generate real text and test the shared editor endpoint.
CI supplies that model; a model-free run must not be described as inference
acceptance. GTK/WebKitGTK verification belongs to the companion runtime repo.

The shared UI uses its own responsive light/dark styling. This is a native app
window with shared web content, not a fully native Liquid Glass interface.


### Installing and updating the desktop app

The DMG app offers **Install and open**, replacing `/Applications/Geist.app` in
place. The candidate is copied and signature-checked before replacement; failed
copy/validation leaves the installed bundle intact. Models, download fragments,
preferences and credentials are outside the bundle and are preserved.

From this release, a stale mounted copy opens an equal/newer installed version.
The new CLI checks the shared service version and upgrades an older versioned
service only while idle. Pre-versioned services need one confirmed restart;
newer services are never silently downgraded. Existing older DMGs cannot acquire
this behavior retroactively: eject them after installation.

Sparkle checks for signed updates daily by default. It replaces the installed
app, rather than creating a second versioned app. Public delivery still requires
the notarized release and signed appcast; local ad-hoc DMGs do not satisfy that
gate. The default window is at most 780 × 620 points and scales down on smaller
screens. Download speed and remaining time are estimates from recent bytes
received in the current window, not throughput guarantees.

### Model performance

The active model has one metric row: tokens/s for the last completed test reply,
current resident RAM of the shared model process and model file size. Clicking
that row or its chevron expands machine/OS, logical CPUs, available RAM,
normalized process CPU load, output count and reply timings directly underneath.
There is no separate performance section in the sidebar. The panel supports
keyboard scrolling and stays inside small windows without moving the composer.
Escape or clicking outside closes it; changing the model clears old reply metrics.
Missing measurements remain unknown; stopped replies have no final speed.
See the pinned runtime’s `docs/INSTALL.md` for exact definitions. The surface is
white with a light gray catalog and blue actions; green marks downloaded models.
