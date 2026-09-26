# Geist — menu bar app for geist-serve on macOS (Apple Silicon, macOS 14+).
#
#> make           build/Geist.app (swift build + bundle, ad-hoc signed)
#> make run       build and launch it
#> make test      bundle sanity + server-process integration (needs a GGUF, else skips)
#> make clean

VERSION ?= 0.0.0-dev
RUNTIME_DIR ?= ../geist-serve

.PHONY: all run test clean help runtime dmg
all: build/Geist.app

help:
	@grep "^#>" Makefile | cut -c4-

runtime:
	sh scripts/prepare-runtime.sh "$(RUNTIME_DIR)"

build/Geist.app: runtime Package.swift $(wildcard Sources/Geist/*.swift) Resources/Info.plist scripts/bundle.sh
	swift build -c release
	VERSION=$(VERSION) sh scripts/bundle.sh

run: build/Geist.app
	open build/Geist.app

test: build/Geist.app
	python3 tests/distribution_test.py
	sh tests/bundle_sanity.sh
	python3 tests/runtime.py

dmg: build/Geist.app
	VERSION=$(VERSION) sh scripts/dmg.sh

clean:
	rm -rf build .build
