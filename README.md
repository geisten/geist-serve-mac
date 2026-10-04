# geisten for macOS

**Runs here. Stays here.** A desktop model manager for one shared local model service.
Download a suggested model once, then connect the terminal, Continue in VS Code
or OpenCode through the same geistd. The current gateway supports text chat;
agent tools are explicitly unsupported. geisten sends no prompts to a cloud
service; connected editors have their own storage and telemetry settings.

Apple Silicon, macOS 14+. This is a development preview: there is no public
release yet. Local builds are ad-hoc signed; public distribution waits for
Developer ID signing and notarization (#6).

## Install

- **DMG:** open `geisten-<version>-arm64.dmg` and choose **Install and open**. The
  app copies itself to `/Applications/geisten.app`, checks the copy's signature
  and replaces an older version in place. Models and settings are kept.
- **Homebrew cask:** planned as `brew install --cask geisten/tap/geisten` once the
  first notarized DMG is published (#7). Until then, build a DMG yourself
  (see *Build a local app and DMG* below). The tap's `Formula/geist.rb` is the
  separate command-line engine and is unrelated to this app.

## First launch

1. geisten opens its window with the model list. Each model has a symbol:
   ✓ good choice, ◐ usable with limits, ✗ not recommended here, ? not
   measured yet. The words behind each symbol are in its tooltip. A line
   above the list names the best installed model; a model to start with is
   marked as the suggested start, with its download size.
2. Click a model's name to download and start it. Downloads over 1 GB ask
   first and show their size; you can pause, resume or remove a download from
   its row. Every download is checked against its SHA-256 before use.
3. When the model is ready, try it in **Quick test** or connect a program.
4. The stopwatch next to an installed model measures its speed on this Mac;
   the chart symbol above the list opens **Compare models**, where you can
   change what counts as fast enough and reliable enough.

Nothing is sent to a cloud service. The share of correct answers comes from a
small reference test of each model (geist-serve `docs/MINI-BENCHMARK.md`), not
from your own tasks: check answers before you rely on them.

## The menu bar

The menu shows the active model and service status, and offers **Models**,
**Settings** (⌘,), **Connect a program**, **Start at Login**, **Show Data
Folder**, **Check for Updates…**, **Stop model service** and **Quit geisten**.
Closing the window or quitting geisten keeps the model service running for your
editors and the terminal; **Stop model service** stops it. The interface is in
German or English: it follows the system language until you choose one in
Settings.

## Connect a program

**Connect a program** shows the local endpoint and model and copies a ready
configuration for the terminal (curl), Continue (VS Code) or OpenCode. The
copied configuration contains your private local key; keep it out of
repositories. The bundled command-line client is
`/Applications/geisten.app/Contents/MacOS/geist-cli` (`geist-cli chat`,
`geist-cli config continue`, `geist-cli config opencode`). Text chat only;
agent tools are rejected. Step-by-step setup for each program is in
[docs/CLIENTS.md](https://github.com/geisten/geist-serve/blob/main/docs/CLIENTS.md);
see also the shared
[app guide](https://github.com/geisten/geist-serve/blob/main/docs/APP.md#shared-editor-endpoint).

## Where your data lives

- `~/Library/Application Support/geisten/`: downloaded models (`models/`), the
  private API key and the connection descriptor.
- Preferences such as the interface language: the `com.geisten.geist` domain.
- Nothing lives inside `geisten.app`, so replacing or updating the app keeps it.

## Uninstall

1. In the menu choose **Stop model service**, then **Quit geisten**.
2. If you enabled **Start at Login**, switch it off first (or remove geisten under
   System Settings → General → Login Items).
3. Delete `/Applications/geisten.app`.
4. To remove models, key and settings as well:

   ```sh
   rm -rf ~/Library/Application\ Support/geisten
   rm -f ~/Library/Application\ Support/Geist   # link left by the rename, if present
   defaults delete com.geisten.geist
   ```

# Development

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
`geisten.app/Contents/MacOS/geist-cli`; no global command is installed automatically.

The first screen shows all catalog models, including missing downloads, with a
platform-checked suggestion ordered first. Clicking a model name or its leading
symbol downloads and starts it; installed models start directly. The leading arrow
becomes a progress ring with pause/resume, then a closed green check ring. There is
no second action arrow, setup button or per-row details section. Suitability uses
chip/check, warning or unavailable symbols with accessible descriptions; capability
badges reflect only features actually implemented by the service (currently text).

**Models** keeps the complete list and **Quick test** together: side by side in the
default window, stacked in narrow ones, with independent scrolling. The test pane
is white and the list light gray. **Connect a program** opens editor setup.
The metric row below the active model expands machine and response measurements.
**Settings** is a separate tab with language, CPU execution information and storage. The gear opens settings directly. The interface follows the OS language
(German, otherwise English) until an explicit language is selected. **System language**
restores automatic detection. This preference also updates native menu labels and
survives reconnects; it does not translate existing input or model responses.
The white interface uses labeled icons for common actions and keeps the active
model's processor choice and typical speed beside it; memory and file size are
in **Measurements**. The native menu shows the active model and status and offers direct
**Models**, **Settings** (⌘,) and **Connect a program** route without reloading.

**Quick test** is optional. Enter sends, Shift + Enter inserts a newline, and
follow-ups use this window's conversation. Explicit model choices, answer language
and per-model preview consent persist. The test lives only in page memory and
is cleared by Clear test, reloading or quitting.
Hardware suitability does not establish answer quality.

See the shared [app guide](https://github.com/geisten/geist-serve/blob/main/docs/APP.md)
for the catalog, model licenses, memory assumptions, privacy boundary and
Pi desktop/SSH setup.

## Build a local app and DMG

Use the companion geist-serve checkout containing `App.mk`:

```sh
make RUNTIME_DIR=../geist-serve
make test RUNTIME_DIR=../geist-serve
make dmg RUNTIME_DIR=../geist-serve VERSION=0.0.0-dev
make run RUNTIME_DIR=../geist-serve
```

The build produces `build/geisten.app` and `build/geisten-0.0.0-dev-arm64.dmg`.
It builds the C23 runtime and the pinned inference engine with static
OpenMP, and rejects Homebrew runtime-library dependencies. The downloaded
model is not included. A verified prebuilt runtime can instead be supplied in
`GEIST_RUNTIME_BIN_DIR`; it must contain executable `geist`, `geist-app` and
`geistd` files for Apple Silicon. The bundle renames `geist` to `geist-cli` to
avoid colliding with `geisten` on case-insensitive filesystems.

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

Models stay in `~/Library/Application Support/geisten/models`. Catalog files
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

The DMG app offers **Install and open**, replacing `/Applications/geisten.app` in
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

Beside the active model, each processor choice shows its typical speed ("Not
measured yet" until it has one); ★ marks the recommended processor. The
**Measurements** icon opens a dialog with current memory (process RSS, Metal
allocation, file size, each with its source in plain words), the local
performance profile per processor, machine/OS details and recent observations.
Escape or clicking outside closes it; changing the model clears old reply metrics.
Missing measurements remain unknown; stopped replies have no final speed.
See the pinned runtime’s `docs/INSTALL.md` for exact definitions. The surface is
white with a light gray catalog and blue actions; green marks downloaded models.

Model rows expose removal of local files without removing the catalog choice.
An idle active model is stopped as part of confirmed deletion; busy work blocks
deletion. Suitability badges identify resource constraints, with tooltip and accessible descriptions.
The active model header has a status dot; the composer holds the test-reset action.
