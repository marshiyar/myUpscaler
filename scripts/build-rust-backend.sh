#!/bin/bash
# Builds the Rust backend (backend/) as the static library the app links: backend/target/<target>/release/libup60p.a.
# Runs as the first Xcode build phase, and works from a shell too. Always an optimised build: the filters are too
# slow to use unoptimised.
set -euo pipefail

repo_dir=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

if ! command -v cargo >/dev/null; then
  echo 'error: Rust is not installed. Install it from https://rustup.rs and build again.' >&2
  exit 1
fi
if [[ ! -d "$repo_dir/third_party/mpvfx-media/lib" ]]; then
  echo 'error: The MpVFX media engine is missing. Run bash scripts/prepare-media-engine.sh before building.' >&2
  exit 1
fi

# rust-toolchain.toml at the repository root pins the compiler; rustup reads it from the working directory.
cd "$repo_dir"
target=aarch64-apple-darwin
if ! rustup target list --installed 2>/dev/null | grep -qx "$target"; then
  rustup target add "$target"
fi
# Xcode's deployment target also sets the minimum macOS of the Rust objects.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.2}"
cargo build --manifest-path "$repo_dir/backend/Cargo.toml" --release --lib --target "$target"
test -f "$repo_dir/backend/target/$target/release/libup60p.a"
