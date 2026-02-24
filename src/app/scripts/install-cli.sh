#!/usr/bin/env bash
# scripts/install-cli.sh
# Builds the r2-cli crate in release mode and installs the `r2drop` binary.
# Default install location: /usr/local/bin (requires sudo).
#
# Usage:
#   ./scripts/install-cli.sh                        # Install to /usr/local/bin
#   ./scripts/install-cli.sh --prefix ~/.local       # Install to ~/.local/bin
#
# Requirements:
#   - rustup with stable toolchain (1.93+)

set -euo pipefail

# --- Configuration -----------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE_DIR="$APP_DIR/engine"
BINARY_NAME="r2drop"
INSTALL_PREFIX="/usr/local"

# --- Parse arguments ----------------------------------------------------------

for arg in "$@"; do
    case "$arg" in
        --prefix)
            shift
            INSTALL_PREFIX="${1:-}"
            if [[ -z "$INSTALL_PREFIX" ]]; then
                echo "Error: --prefix requires a path argument"
                exit 1
            fi
            ;;
        --prefix=*)
            INSTALL_PREFIX="${arg#--prefix=}"
            ;;
        --help|-h)
            echo "Usage: $0 [--prefix <path>]"
            echo ""
            echo "  --prefix <path>   Install to <path>/bin (default: /usr/local)"
            echo "  --help            Show this help message"
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$arg'"
            echo "Run '$0 --help' for usage."
            exit 1
            ;;
    esac
done

INSTALL_DIR="$INSTALL_PREFIX/bin"

# --- Preflight checks --------------------------------------------------------

if ! command -v cargo &>/dev/null; then
    echo "Error: cargo not found. Install Rust via https://rustup.rs"
    exit 1
fi

# --- Build --------------------------------------------------------------------

echo "Building r2-cli (release)..."
cargo build --manifest-path "$ENGINE_DIR/Cargo.toml" \
    -p r2-cli --release

# The binary lands at engine/target/release/r2drop
BUILT_BINARY="$ENGINE_DIR/target/release/$BINARY_NAME"

if [[ ! -f "$BUILT_BINARY" ]]; then
    echo "Error: Built binary not found at $BUILT_BINARY"
    exit 1
fi

# --- Install ------------------------------------------------------------------

echo "Installing $BINARY_NAME to $INSTALL_DIR..."

# Create the install directory if it doesn't exist
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo "  Creating $INSTALL_DIR (may require sudo)..."
    sudo mkdir -p "$INSTALL_DIR"
fi

# Check if we need sudo for the install directory
if [[ -w "$INSTALL_DIR" ]]; then
    cp "$BUILT_BINARY" "$INSTALL_DIR/$BINARY_NAME"
else
    echo "  (requires sudo)"
    sudo cp "$BUILT_BINARY" "$INSTALL_DIR/$BINARY_NAME"
fi

chmod +x "$INSTALL_DIR/$BINARY_NAME"

# --- Verify -------------------------------------------------------------------

INSTALLED_PATH="$(command -v "$BINARY_NAME" 2>/dev/null || echo "$INSTALL_DIR/$BINARY_NAME")"
echo ""
echo "Installed: $INSTALLED_PATH"
echo "Version:   $("$INSTALL_DIR/$BINARY_NAME" --version 2>/dev/null || echo "unknown")"
