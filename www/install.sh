#!/usr/bin/env sh
# src/scripts/install.sh
# Downloads and installs the r2drop CLI from GitHub Releases.
#
# Usage:
#   curl -fsSL https://r2drop.com/install.sh | bash
#   curl -fsSL https://r2drop.com/install.sh | bash -s -- --bin-dir ~/.local/bin
#   curl -fsSL https://r2drop.com/install.sh | bash -s -- --version cli-v0.1.0

set -eu

# ── Terminal colors ───────────────────────────────────────────────────────────
BOLD="$(tput bold 2>/dev/null || printf '')"
GREEN="$(tput setaf 2 2>/dev/null || printf '')"
YELLOW="$(tput setaf 3 2>/dev/null || printf '')"
RED="$(tput setaf 1 2>/dev/null || printf '')"
BLUE="$(tput setaf 4 2>/dev/null || printf '')"
NO_COLOR="$(tput sgr0 2>/dev/null || printf '')"

REPO="superhumancorp/r2drop"
BINARY_NAME="r2drop"
BASE_URL="${BASE_URL:-https://github.com/${REPO}/releases}"
RELEASES_API_URL="${RELEASES_API_URL:-https://api.github.com/repos/${REPO}/releases}"

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
    darwin) printf 'macos' ;;
    *)
      error "Unsupported OS: $os — R2Drop CLI is macOS only."
      error "Download manually: https://github.com/${REPO}/releases"
      exit 1
      ;;
  esac
}

detect_arch() {
  arch="$(uname -m)"
  case "$arch" in
    x86_64 | amd64)   printf 'x86_64' ;;
    aarch64 | arm64)  printf 'arm64' ;;
    *)
      error "Unsupported architecture: $arch"
      exit 1
      ;;
  esac
}

# ── Asset naming (matches .github/workflows/cli-release.yml) ────────────────
asset_name() {
  os="$1"
  arch="$2"
  case "${os}-${arch}" in
    macos-arm64)    printf 'r2drop-macos-arm64.tar.gz' ;;
    macos-x86_64)   printf 'r2drop-macos-x86_64.tar.gz' ;;
    *)
      error "Unsupported platform combo: ${os}-${arch}"
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

# ── GitHub CLI helpers (private repo fallback) ───────────────────────────────
resolve_version_via_gh() {
  if ! has gh; then
    return 1
  fi

  gh release list -R "$REPO" --limit 100 --json tagName --jq '.[].tagName' 2>/dev/null \
    | grep '^cli-v' \
    | head -1
}

download_release_asset() {
  tag="$1"
  asset="$2"
  dest="$3"
  url="${BASE_URL}/download/${tag}/${asset}"

  if download "$url" "$dest"; then
    return 0
  fi

  # Private-repo fallback: use authenticated gh CLI download if available.
  if has gh; then
    tmpdir="$(mktemp -d /tmp/r2drop-asset-XXXXXX 2>/dev/null || mktemp -d)"
    if gh release download "$tag" -R "$REPO" -p "$asset" -D "$tmpdir" >/dev/null 2>&1; then
      mv "$tmpdir/$asset" "$dest"
      rm -rf "$tmpdir"
      return 0
    fi
    rm -rf "$tmpdir"
  fi

  return 1
}

# ── Resolve version to a concrete CLI release tag (cli-vX.Y.Z) ──────────────
resolve_version() {
  if [ "$VERSION" = "latest" ]; then
    response_file="$(mktemp /tmp/r2drop-releases-XXXXXX.json)"
    http_code="$(
      curl --silent --location \
        --output "$response_file" \
        --write-out '%{http_code}' \
        --header 'Accept: application/vnd.github+json' \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        --header 'User-Agent: r2drop-install' \
        "${RELEASES_API_URL}?per_page=50" 2>/dev/null || true
    )"
    response="$(cat "$response_file" 2>/dev/null || true)"
    rm -f "$response_file"

    # Pick the newest release with a cli-v* tag.
    # NOTE: We avoid removing all whitespace globally because that can collapse
    # lines and break matching when a non-CLI release appears first.
    resolved="$(
      printf '%s\n' "$response" \
        | awk -F'"tag_name"[[:space:]]*:[[:space:]]*"' '
            {
              for (i = 2; i <= NF; i++) {
                split($i, parts, "\"");
                if (parts[1] ~ /^cli-v/) {
                  print parts[1];
                  exit;
                }
              }
            }
          ' \
        | head -1
    )"

    if [ -z "$resolved" ]; then
      resolved="$(resolve_version_via_gh || true)"
    fi

    if [ -z "$resolved" ]; then
      error "No published CLI releases found for ${REPO}."
      if [ "$http_code" = "404" ]; then
        error "GitHub returned Not Found. This usually means the repo is private for anonymous requests."
        error "Use an authenticated GitHub CLI session (gh auth login), or make releases public."
      else
        error "The GitHub releases API may be private/unavailable, or no cli-v* release has been published yet."
      fi
      error "Check https://github.com/${REPO}/releases for available versions."
      error "To install a specific CLI release: curl ... | bash -s -- --version v0.1.0 (maps to cli-v0.1.0)"
      exit 1
    fi
    printf '%s' "$resolved"
  else
    case "$VERSION" in
      cli-v*) printf '%s' "$VERSION" ;;
      v*)     printf 'cli-%s' "$VERSION" ;;
      *)      printf 'cli-v%s' "$VERSION" ;;
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
      printf 'Usage: install.sh [--bin-dir DIR] [--version cli-vX.Y.Z]\n'
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
info "Installing ${BOLD}r2drop${NO_COLOR}..."

OS="$(detect_os)"
ARCH="$(detect_arch)"
TAG="$(resolve_version)"
BIN_DIR="$(pick_bin_dir)"

# Asset name must match .github/workflows/cli-release.yml upload naming
ASSET="$(asset_name "$OS" "$ARCH")"
URL="${BASE_URL}/download/${TAG}/${ASSET}"

info "Version:  ${BLUE}${TAG}${NO_COLOR}"
info "Platform: ${BLUE}${ARCH}-${OS}${NO_COLOR}"
info "Install:  ${BLUE}${BIN_DIR}${NO_COLOR}"
printf '\n'

# Download to a temp file
TMPDIR="$(mktemp -d /tmp/r2drop-install-XXXXXX 2>/dev/null || mktemp -d)"
TMPFILE="${TMPDIR}/r2drop.tar.gz"
trap 'rm -rf "$TMPDIR"' EXIT

info "Downloading ${URL}..."
if ! download_release_asset "$TAG" "$ASSET" "$TMPFILE"; then
  error "Download failed. Check the version and your internet connection."
  error "URL: ${URL}"
  if has gh; then
    error "Tip: run 'gh auth login' to enable authenticated downloads for private repos."
  fi
  exit 1
fi

# Verify SHA-256 checksum (if checksum file is available)
CHECKSUM_ASSET="${ASSET}.sha256"
CHECKSUM_FILE="${TMPDIR}/checksum.sha256"
if download_release_asset "$TAG" "$CHECKSUM_ASSET" "$CHECKSUM_FILE" 2>/dev/null; then
  EXPECTED="$(awk '{print $1}' "$CHECKSUM_FILE")"
  ACTUAL="$(shasum -a 256 "$TMPFILE" | awk '{print $1}')"
  if [ "$EXPECTED" != "$ACTUAL" ]; then
    error "Checksum verification failed!"
    error "Expected: $EXPECTED"
    error "Actual:   $ACTUAL"
    error "The downloaded binary may have been tampered with. Aborting."
    exit 1
  fi
  completed "Checksum verified (SHA-256)"
else
  warn "No checksum file found for this release. Skipping verification."
fi

# Extract the binary
mkdir -p "$BIN_DIR"
tar -xzf "$TMPFILE" -C "$BIN_DIR" "$BINARY_NAME"
chmod +x "${BIN_DIR}/${BINARY_NAME}"

printf '\n'
completed "r2drop ${TAG} installed to ${BIN_DIR}/r2drop"

# Warn if BIN_DIR is not in PATH
if ! echo "$PATH" | grep -q "$BIN_DIR"; then
  printf '\n'
  warn "${BIN_DIR} is not in your \$PATH."
  warn "Add this to your shell profile:"
  printf '\n    export PATH="%s:$PATH"\n\n' "$BIN_DIR"
fi
