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
    make -C "$source_dir" GEISTD_OUTPUT=build/geistd-execution build/geistd-execution app GEIST_STATIC_OMP=1
    runtime_dir=$source_dir
    daemon_binary=$source_dir/build/geistd-execution
else
    daemon_binary=$runtime_dir/geistd
fi
mkdir -p build
license_file="$runtime_dir/web/vendor/marked-LICENSE"
[ -f "$license_file" ] || license_file="$runtime_dir/marked-LICENSE"
[ -f "$license_file" ] || { echo 'Missing Marked license in runtime input' >&2; exit 1; }
cp "$license_file" build/marked-LICENSE
math_license="$runtime_dir/web/vendor/katex-LICENSE"
[ -f "$math_license" ] || math_license="$runtime_dir/katex-LICENSE"
if [ -f "$math_license" ]; then
    cp "$math_license" build/katex-LICENSE
elif [ -f "$runtime_dir/web/vendor/katex.min.js" ]; then
    echo 'Missing KaTeX license in math-enabled runtime input' >&2; exit 1
else
    # Older pinned runtimes contain only Marked; do not attach stale licenses.
    rm -f build/katex-LICENSE
fi
for binary in geist geist-app geistd; do
    input_binary=$runtime_dir/$binary
    [ "$binary" != geistd ] || input_binary=$daemon_binary
    # The CLI is geisten since geist-serve#96; geist is its alias (older runtimes: the binary).
    [ "$binary" != geist ] || [ ! -x "$runtime_dir/geisten" ] || input_binary=$runtime_dir/geisten
    [ -x "$input_binary" ] || { echo "Missing runtime: $input_binary" >&2; exit 1; }
    if otool -L "$input_binary" | grep -q '/opt/homebrew\|/usr/local/'; then
        echo "Runtime depends on a developer installation: $binary" >&2; exit 1
    fi
    # Replace the inode instead of overwriting an executable that a previous
    # native test may still have mapped. macOS caches code signatures by vnode.
    temporary=$(mktemp "build/.runtime-${binary}.XXXXXX")
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    cp "$input_binary" "$temporary"
    chmod 755 "$temporary"
    mv "$temporary" "build/$binary"
    trap - EXIT HUP INT TERM
done
shasum -a 256 build/geist build/geist-app build/geistd > build/RUNTIME-SHA256SUMS

python3 scripts/engine-manifest.py build/geistd build/ENGINE.json
