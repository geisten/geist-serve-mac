# Geist — menu bar app for geist-serve on macOS (Apple Silicon, macOS 14+).
#
#> make           build/Geist.app (swift build + bundle, ad-hoc signed)
#> make run       build and launch it
#> make test      bundle sanity + server-process integration (needs a GGUF, else skips)
#> make clean

VERSION ?= 0.0.0-dev

.PHONY: all run test clean help
all: build/Geist.app

help:
	@grep "^#>" Makefile | cut -c4-

build/geist-serve: scripts/fetch-server.sh
	sh scripts/fetch-server.sh $@

build/Geist.app: build/geist-serve Package.swift $(wildcard Sources/Geist/*.swift) Resources/Info.plist scripts/bundle.sh
	swift build -c release 2>&1 | grep -vE '^(Building|Build complete|\[)' || true
	VERSION=$(VERSION) sh scripts/bundle.sh

run: build/Geist.app
	open build/Geist.app

test: build/Geist.app
	sh tests/bundle_sanity.sh
	sh tests/server_process.sh
	sh tests/models.sh
	sh tests/settings.sh
	sh tests/update.sh

clean:
	rm -rf build .build
