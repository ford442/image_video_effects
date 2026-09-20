#!/usr/bin/env bash
#
# Builds tools/naga_wasm and installs the artifact at public/wasm/naga_wasm.wasm.
#
# The artifact is committed, like public/wasm/pixelocity_wasm.wasm, so that
# `npm run verify:naga-wasm`, CI and `npm start` all work without a Rust
# toolchain. Re-run this whenever src/lib.rs or the naga pin in Cargo.toml
# changes — scripts/validate_wasm_artifacts.js fails on a stale artifact.
set -euo pipefail

CRATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$CRATE_DIR/../.." && pwd)"
TARGET="wasm32-unknown-unknown"
OUT="$REPO_ROOT/public/wasm/naga_wasm.wasm"

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo not found. Install Rust (https://rustup.rs) to rebuild naga_wasm." >&2
  echo "       The committed artifact at public/wasm/naga_wasm.wasm works without it." >&2
  exit 1
fi

if ! rustup target list --installed 2>/dev/null | grep -qx "$TARGET"; then
  echo "Installing Rust target $TARGET..."
  rustup target add "$TARGET"
fi

echo "Building naga_wasm ($TARGET, release)..."
cargo build --release --target "$TARGET" --manifest-path "$CRATE_DIR/Cargo.toml"

BUILT="$CRATE_DIR/target/$TARGET/release/naga_wasm.wasm"
[ -f "$BUILT" ] || { echo "error: expected artifact not found at $BUILT" >&2; exit 1; }

cp "$BUILT" "$OUT"
echo "Installed $(wc -c < "$OUT") bytes -> public/wasm/naga_wasm.wasm"

# Report the naga version actually linked, so a pin bump is visible in the log.
grep -E '^name = "naga"$' -A1 "$CRATE_DIR/Cargo.lock" 2>/dev/null | tail -1 || true
