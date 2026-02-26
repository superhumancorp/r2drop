#!/usr/bin/env bash
# scripts/build-rust.sh
# Compiles the Rust workspace (r2-core, r2-ffi, r2-cli).
# Produces libr2_ffi.a (universal binary for ARM + x86_64) and r2_ffi.h.
# Copies outputs to where the R2Bridge Swift package expects them.
#
# Usage:
#   ./scripts/build-rust.sh              # Debug build (fast, for development)
#   ./scripts/build-rust.sh --release    # Release build (optimized, for distribution)
#
# Requirements:
#   - rustup with stable toolchain (1.93+)
#   - Both targets installed: aarch64-apple-darwin, x86_64-apple-darwin
#     Run: rustup target add aarch64-apple-darwin x86_64-apple-darwin

set -euo pipefail

# --- Configuration -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_DIR="$APP_DIR/engine"
BRIDGE_HEADER_DIR="$APP_DIR/Packages/R2Bridge/Sources/R2BridgeC/include"

ARM_TARGET="aarch64-apple-darwin"
X86_TARGET="x86_64-apple-darwin"
DEPLOYMENT_TARGET_DEFAULT="13.0"

# --- Parse arguments ----------------------------------------------------------

PROFILE="debug"
CARGO_FLAGS=""

for arg in "$@"; do
    case "$arg" in
        --release)
            PROFILE="release"
            CARGO_FLAGS="--release"
            ;;
        --help|-h)
            echo "Usage: $0 [--release]"
            echo ""
            echo "  --release   Build with optimizations (slower compile, faster binary)"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$arg'"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

# --- Preflight checks --------------------------------------------------------

if ! command -v rustup &>/dev/null; then
    echo "Error: rustup not found. Install via https://rustup.rs"
    exit 1
fi

# Prefer rustup's cargo/rustc over Homebrew's (which may be outdated).
# rustup proxies live in ~/.cargo/bin and respect rust-toolchain.toml.
RUSTUP_CARGO="$(rustup which cargo 2>/dev/null || true)"
if [[ -n "$RUSTUP_CARGO" ]]; then
    RUSTUP_BIN_DIR="$(dirname "$RUSTUP_CARGO")"
    export PATH="$HOME/.cargo/bin:$RUSTUP_BIN_DIR:$PATH"
    echo "Using rustup cargo: $(which cargo) ($(cargo --version))"
else
    echo "Warning: Could not locate rustup cargo, falling back to PATH"
fi

if ! command -v cargo &>/dev/null; then
    echo "Error: cargo not found. Install Rust via https://rustup.rs"
    exit 1
fi

# Ensure both targets are installed
for target in "$ARM_TARGET" "$X86_TARGET"; do
    if ! rustup target list --installed | grep -q "$target"; then
        echo "Installing Rust target: $target"
        rustup target add "$target"
    fi
done

# --- Build --------------------------------------------------------------------

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-$DEPLOYMENT_TARGET_DEFAULT}"
MIN_VERSION_FLAG="-mmacosx-version-min=$MACOSX_DEPLOYMENT_TARGET"

# Ensure Rust and any C/ASM dependencies (via cc crate) inherit the same min macOS target.
export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=$MIN_VERSION_FLAG"
export CFLAGS_aarch64_apple_darwin="${CFLAGS_aarch64_apple_darwin:-} $MIN_VERSION_FLAG"
export CFLAGS_x86_64_apple_darwin="${CFLAGS_x86_64_apple_darwin:-} $MIN_VERSION_FLAG"
export CXXFLAGS_aarch64_apple_darwin="${CXXFLAGS_aarch64_apple_darwin:-} $MIN_VERSION_FLAG"
export CXXFLAGS_x86_64_apple_darwin="${CXXFLAGS_x86_64_apple_darwin:-} $MIN_VERSION_FLAG"

echo "Building Rust workspace ($PROFILE)..."
echo "  Engine dir: $ENGINE_DIR"
echo "  macOS deployment target: $MACOSX_DEPLOYMENT_TARGET"

# Build for ARM (Apple Silicon)
echo "  -> $ARM_TARGET"
cargo build --manifest-path "$ENGINE_DIR/Cargo.toml" \
    --workspace --target "$ARM_TARGET" $CARGO_FLAGS

# Build for x86_64 (Intel)
echo "  -> $X86_TARGET"
cargo build --manifest-path "$ENGINE_DIR/Cargo.toml" \
    --workspace --target "$X86_TARGET" $CARGO_FLAGS

# --- Create universal binary --------------------------------------------------

ARM_LIB="$ENGINE_DIR/target/$ARM_TARGET/$PROFILE/libr2_ffi.a"
X86_LIB="$ENGINE_DIR/target/$X86_TARGET/$PROFILE/libr2_ffi.a"
UNIVERSAL_DIR="$ENGINE_DIR/target/$PROFILE"
UNIVERSAL_LIB="$UNIVERSAL_DIR/libr2_ffi.a"

if [[ ! -f "$ARM_LIB" ]]; then
    echo "Error: ARM library not found at $ARM_LIB"
    exit 1
fi
if [[ ! -f "$X86_LIB" ]]; then
    echo "Error: x86_64 library not found at $X86_LIB"
    exit 1
fi

mkdir -p "$UNIVERSAL_DIR"

echo "Creating universal binary..."
lipo -create "$ARM_LIB" "$X86_LIB" -output "$UNIVERSAL_LIB"
echo "  -> $UNIVERSAL_LIB"

# Verify the universal binary contains both architectures
lipo -info "$UNIVERSAL_LIB"

# --- Copy header --------------------------------------------------------------

FFI_HEADER="$ENGINE_DIR/r2-ffi/r2_ffi.h"

if [[ ! -f "$FFI_HEADER" ]]; then
    echo "Error: r2_ffi.h not found at $FFI_HEADER"
    echo "cbindgen may have failed during the build."
    exit 1
fi

mkdir -p "$BRIDGE_HEADER_DIR"
cp "$FFI_HEADER" "$BRIDGE_HEADER_DIR/r2_ffi.h"
echo "Header copied to $BRIDGE_HEADER_DIR/r2_ffi.h"

# --- Summary ------------------------------------------------------------------

echo ""
echo "Build complete ($PROFILE)."
echo "  Library: $UNIVERSAL_LIB ($(du -h "$UNIVERSAL_LIB" | cut -f1))"
echo "  Header:  $BRIDGE_HEADER_DIR/r2_ffi.h"
