# superhumancorp/homebrew-tap

Homebrew tap for [R2Drop](https://r2drop.com) — macOS menu bar app and CLI for Cloudflare R2.

## Setup

```sh
brew tap superhumancorp/tap
```

## Install

```sh
# macOS menu bar app
brew install --cask superhumancorp/tap/r2drop

# CLI (macOS + Linux)
brew install --formula superhumancorp/tap/r2drop
```

## curl installer (CLI only)

```sh
curl -fsSL https://r2drop.com/install.sh | bash
```

## Packages

| Package | Type | Description |
|---------|------|-------------|
| `r2drop` | Cask | macOS menu bar app (.dmg) |
| `r2drop` | Formula | CLI binary (macOS + Linux, arm64 + x86_64) |

Notes:
- Use `brew install --cask superhumancorp/tap/r2drop` for the macOS app.
- Use `brew install --formula superhumancorp/tap/r2drop` for the CLI.
