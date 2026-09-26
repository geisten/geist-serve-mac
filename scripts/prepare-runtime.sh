#!/bin/sh
# Build the shared C23 application and its pinned, unmodified engine.
# A release can provide an already built directory with GEIST_RUNTIME_BIN_DIR.
set -eu
cd "$(dirname "$0")/.."
source_dir=${1:-../geist-serve}
runtime_dir=${GEIST_RUNTIME_BIN_DIR:-}
if [ -z "$runtime_dir" ]; then
    [ -f "$source_dir/App.mk" ] || {
        echo 'Build requires the geist-serve checkout containing geist-app.' >&2
        echo 'Set RUNTIME_DIR=/path/to/that/checkout, or GEIST_RUNTIME_BIN_DIR to verified release binaries.' >&2
        exit 1
    }
    make -C "$source_dir" geistd app GEIST_STATIC_OMP=1
    runtime_dir=$source_dir
fi
mkdir -p build
for binary in geist geist-app geistd; do
    [ -x "$runtime_dir/$binary" ] || { echo "Missing runtime: $runtime_dir/$binary" >&2; exit 1; }
    if otool -L "$runtime_dir/$binary" | grep -q '/opt/homebrew\|/usr/local/'; then
        echo "Runtime depends on a developer installation: $binary" >&2; exit 1
    fi
    cp "$runtime_dir/$binary" "build/$binary"
done
shasum -a 256 build/geist build/geist-app build/geistd > build/RUNTIME-SHA256SUMS
