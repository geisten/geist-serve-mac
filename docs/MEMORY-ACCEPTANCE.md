# Scoped memory acceptance

The shared runtime distinguishes process RSS from allocated Metal resources.
These scopes can overlap on Apple Silicon; neither their sum nor model file
size is presented as unique physical memory. Unsupported, stale and failed
samples remain unavailable rather than becoming zero.

The normal native suite exercises DE/EN, keyboard navigation, narrow windows,
zoom, stable transcript geometry and synthetic scope/availability cases. It
also covers the three-row summary and non-CPU activity rendering. These two
regressions reproduced failures in the previous package before the fixes.

For physical Bonsai acceptance, supply the already cached, catalog-matching
PQ2_0 artifact. The test clones it into a temporary directory, runs real
CPU → Metal → CPU requests and records ready/response memory snapshots and
screenshots. It checks distinct scopes, fresh generation ownership, visible
summary rows, absence of render errors and reaping of the previous runtime.
It does not download the large artifact or touch the normal installation.

After building the development bundle, run:

```sh
GEIST_DESKTOP_RUNTIME="$PWD/build/Geist.app/Contents/MacOS" \
GEIST_BONSAI_TEST_MODEL=/path/to/Ternary-Bonsai-2-27B-PQ2_0.gguf \
GEIST_DESKTOP_EVIDENCE=/path/to/a-new-evidence-directory \
swift test --filter DesktopWebViewTests.testPackagedBonsaiMemoryAcrossCPUAndMetal
```

Use sufficient available RAM and a fresh evidence directory. The large-model
test explicitly skips when its inputs are absent; normal CI does not claim
physical Bonsai acceptance from that skip. Preserve failed runs separately.

The UI records the persistent response footer instead of using the transient
`lastReply` summary as a completion signal. Polling during this opt-in test
also makes observation independent of background WebView timer throttling.
Backend completion and successful UI rendering are checked separately.

Installation testing remains separate (`make test-dmg` with
`GEIST_TEST_MODEL`): actual mounted image, copied installation, real response,
restart, manual replacement and removal that preserves service data.
Ad-hoc development packaging does not establish Apple notarization or
Gatekeeper acceptance for a published release.
