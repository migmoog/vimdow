#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUST_DIR="$SCRIPT_DIR/rust"
BIN_DIR="$SCRIPT_DIR/godot/addons/vimdow/bin"

mkdir -p "$BIN_DIR"

BUILD=${1:-debug}

cargo build --manifest-path "$RUST_DIR/Cargo.toml" $([ "$BUILD" = "release" ] && echo "--release")

case "$(uname -s)" in
  Linux)  LIB="libvimdow.so" ;;
  Darwin) LIB="libvimdow.dylib" ;;
  MINGW*|CYGWIN*|MSYS*) LIB="vimdow.dll" ;;
  *) echo "Unsupported OS" && exit 1 ;;
esac

cp "$RUST_DIR/target/$BUILD/$LIB" "$BIN_DIR/$LIB"
echo "Copied $LIB to $BIN_DIR"
