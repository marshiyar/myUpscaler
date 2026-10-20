#!/bin/bash
# Sourced by test scripts that link the app's processing backend: builds the Rust library and its generated header
# (preparing the media engine first) and sets RUST_BACKEND_FLAGS for swiftc.
bash scripts/prepare-media-engine.sh >/dev/null
bash scripts/build-rust-backend.sh >/dev/null
RUST_BACKEND_FLAGS=(
  -import-objc-header backend/target/include/up60p.h
  -L backend/target/aarch64-apple-darwin/release -L third_party/mpvfx-media/lib -lup60p -lmpvfx_ffi
  -Xlinker -rpath -Xlinker "$PWD/third_party/mpvfx-media/lib"
)
