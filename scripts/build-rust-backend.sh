#!/bin/bash
# Builds the Rust backend (backend/) as the static library the app links, backend/target/<target>/release/libup60p.a,
# and generates the header Swift imports it through, backend/target/include/up60p.h (the bridging header). Runs as
# the first Xcode build phase, and works from a shell too. Always an optimised build: the filters are too slow to
# use unoptimised.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
target=aarch64-apple-darwin
# Xcode's deployment target also sets the minimum macOS of the Rust objects.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.2}"
library="$repo_dir/backend/target/$target/release/libup60p.a"
header="$repo_dir/backend/target/include/up60p.h"
stamp="$repo_dir/backend/target/$target/release/.up60p-fingerprint"

if [[ ! -d "$repo_dir/third_party/mpvfx-media/lib" ]]; then
  echo 'error: The MpVFX media engine is missing. Run bash scripts/prepare-media-engine.sh before building.' >&2
  exit 1
fi

# The library only changes with the backend's sources, the toolchain, the media engine package and the deployment
# target. When none of them changed since the last build, the compiled library is reused without running Cargo
# (CI restores it from its cache the same way).
fingerprint=$(
  cd "$repo_dir"
  {
    find backend/src backend/build.rs backend/Cargo.toml backend/Cargo.lock rust-toolchain.toml -type f | LC_ALL=C sort \
      | while read -r file; do printf '%s ' "$file"; shasum -a 256 < "$file"; done
    cat third_party/mpvfx-media/.package 2>/dev/null || true
    echo "$MACOSX_DEPLOYMENT_TARGET"
  } | shasum -a 256 | cut -d' ' -f1
)
if [[ -f $library && -f $header && -f $stamp && $(cat "$stamp") == "$fingerprint" ]]; then
  echo "Rust backend is up to date ($library)"
  exit 0
fi

if ! command -v cargo >/dev/null; then
  echo 'error: Rust is not installed. Install it from https://rustup.rs and build again.' >&2
  exit 1
fi

# rust-toolchain.toml at the repository root pins the compiler; rustup reads it from the working directory.
cd "$repo_dir"
if ! rustup target list --installed 2>/dev/null | grep -qx "$target"; then
  rustup target add "$target"
fi
cargo build --manifest-path "$repo_dir/backend/Cargo.toml" --release --lib --target "$target"
test -f "$repo_dir/backend/target/$target/release/libup60p.a"
cargo run --manifest-path "$repo_dir/backend/Cargo.toml" --release --quiet --bin up60p --target "$target" -- \
  --write-header "$repo_dir/backend/target/include/up60p.h"
test -f "$repo_dir/backend/target/include/up60p.h"
echo "$fingerprint" > "$stamp"
