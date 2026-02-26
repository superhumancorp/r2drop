#!/usr/bin/env sh
# scripts/install.sh
# Downloads and installs r2-cli from GitHub Releases.
#
# Usage:
#   curl -fsSL https://r2drop.com/install.sh | bash
#   curl -fsSL https://r2drop.com/install.sh | bash -s -- --bin-dir ~/.local/bin
#   curl -fsSL https://r2drop.com/install.sh | bash -s -- --version v0.1.0

set -eu

# ── Terminal colors ───────────────────────────────────────────────────────────
BOLD="$(tput bold 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
BLUE="$(tput setaf 4 2>/dev/null || printf '')"
NO_COLOR="$(tput sgr0 2>/dev/null || printf '')"

REPO="superhumancorp/r2drop"
BINARY_NAME="r2-cli"
BASE_URL="https://github.com/${REPO}/releases"

# ── Defaults ──────────────────────────────────────────────────────────────────
BIN_DIR="${BIN_DIR:-}"
VERSION="${VERSION:-latest}"

# ── Helpers ───────────────────────────────────────────────────────────────────
info()      { printf '%s\n' "${BOLD}>${NO_COLOR} $*"; }
warn()      { printf '%s\n' "${YELLOW}! $*${NO_COLOR}"; }
error()     { printf '%s\n' "${RED}x $*${NO_COLOR}" >&2; }
completed() { printf '%s\n' "${GREEN}✓${NO_COLOR} $*"; }
has()       { command -v "$1" >/dev/null 2>&1; }

# ── OS / arch detection ──────────────────────────────────────────────────────
detect_os() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    darwin) printf 'apple-darwin' ;;
    linux)  printf 'unknown-linux-musl' ;;
    *)
      error "Unsupported OS: $os"
      error "Download manually: https://github.com/${REPO}/releases"
      exit 1
      ;;
  esac
}

detect_arch() {
  arch="$(uname -m)"
  case "$arch" in
    x86_64 | amd64)  printf 'x86_64' ;;
    aarch64 | arm64)  printf 'aarch64' ;;
    *)
      error "Unsupported architecture: $arch"
      exit 1
      ;;
  esac
}

# ── Pick install directory ────────────────────────────────────────────────────
pick_bin_dir() {
  if [ -n "$BIN_DIR" ]; then
    printf '%s' "$BIN_DIR"
    return
  fi

  # Prefer ~/.local/bin (no sudo), fall back to /usr/local/bin
  if [ -d "$HOME/.local/bin" ] && echo "$PATH" | grep -q "$HOME/.local/bin"; then
    printf '%s' "$HOME/.local/bin"
  elif [ -w "/usr/local/bin" ]; then
    printf '%s' "/usr/local/bin"
  else
    mkdir -p "$HOME/.local/bin"
    printf '%s' "$HOME/.local/bin"
  fi
}

# ── Download helper ───────────────────────────────────────────────────────────
download() {
  url="$1"
  dest="$2"

  if has curl; then
    curl --fail --silent --location --output "$dest" "$url"
  elif has wget; then
    wget --quiet --output-document="$dest" "$url"
  else
    error "Neither curl nor wget found. Install one and retry."
    exit 1
  fi
}

# ── Resolve "latest" to a concrete version tag ───────────────────────────────
# Uses the GitHub API (more reliable than following the /releases/latest redirect).
resolve_version() {
  if [ "$VERSION" = "latest" ]; then
    api_url="https://api.github.com/repos/${REPO}/releases/latest"
    response="$(curl --fail --silent --location "$api_url" 2>/dev/null || true)"

    # Extract tag_name from JSON response.
    resolved="$(printf '%s' "$response" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' \
      | tr -d '[:space:]')"

    if [ -z "$resolved" ]; then
      error "No published releases found for ${REPO}."
      error "Check https://github.com/${REPO}/releases for available versions."
      error "To install a specific version: curl ... | bash -s -- --version v0.1.0"
      exit 1
    fi
    printf '%s' "$resolved"
  else
    case "$VERSION" in
      v*) printf '%s' "$VERSION" ;;
      *)  printf 'v%s' "$VERSION" ;;
    esac
  fi
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [ "$#" -gt 0 ]; do
  case "$1" in
    -b | --bin-dir)       BIN_DIR="$2";   shift 2 ;;
    -v | --version)       VERSION="$2";   shift 2 ;;
    -b=* | --bin-dir=*)   BIN_DIR="${1#*=}"; shift 1 ;;
    -v=* | --version=*)   VERSION="${1#*=}"; shift 1 ;;
    -h | --help)
      printf 'Usage: install.sh [--bin-dir DIR] [--version vX.Y.Z]\n'
      printf '\n'
      printf '  --bin-dir DIR    Install to DIR (default: ~/.local/bin or /usr/local/bin)\n'
      printf '  --version TAG    Install specific version (default: latest)\n'
      exit 0
      ;;
    *)
      error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ── Main ──────────────────────────────────────────────────────────────────────
printf '\n'
info "Installing ${BOLD}r2-cli${NO_COLOR}..."

OS="$(detect_os)"
ARCH="$(detect_arch)"
TAG="$(resolve_version)"
BIN_DIR="$(pick_bin_dir)"

# Asset name must match GitHub Release upload naming
ASSET="${BINARY_NAME}-${ARCH}-${OS}.tar.gz"
URL="${BASE_URL}/download/${TAG}/${ASSET}"

info "Version:  ${BLUE}${TAG}${NO_COLOR}"
info "Platform: ${BLUE}${ARCH}-${OS}${NO_COLOR}"
info "Install:  ${BLUE}${BIN_DIR}${NO_COLOR}"
printf '\n'

# Download to a temp file
TMPFILE="$(mktemp /tmp/r2-cli-XXXXXX.tar.gz)"
trap 'rm -f "$TMPFILE"' EXIT

info "Downloading ${URL}..."
if ! download "$URL" "$TMPFILE"; then
  error "Download failed. Check the version and your internet connection."
  error "URL: ${URL}"
  exit 1
fi

# Extract the binary
mkdir -p "$BIN_DIR"
tar -xzf "$TMPFILE" -C "$BIN_DIR" "$BINARY_NAME"
chmod +x "${BIN_DIR}/${BINARY_NAME}"

printf '\n'
completed "r2-cli ${TAG} installed to ${BIN_DIR}/r2-cli"

# Warn if BIN_DIR is not in PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  printf '\n'
  warn "${BIN_DIR} is not in your \$PATH."
  warn "Add this to your shell profile:"
  printf '\n    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
fi
