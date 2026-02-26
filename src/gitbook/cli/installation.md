# CLI Installation

The `r2drop` CLI is a standalone binary. It works on macOS and Linux (x86_64 and arm64).

---

## Option 1: Homebrew (Recommended)

```bash
brew tap superhumancorp/tap
brew install superhumancorp/tap/r2-cli
```

This is the easiest method and handles updates automatically via `brew upgrade`.

---

## Option 2: Quick Install Script

```bash
curl -fsSL https://r2drop.com/install.sh | bash
```

Installs `r2drop` to `~/.local/bin`. Works on macOS and Linux.

---

## Option 3: From the macOS App

If you already have R2Drop installed, the app can install the CLI for you.

1. Open R2Drop → **Settings tab → Command Line Interface**
2. Click **Install CLI**

The CLI is installed to `~/.local/bin/r2drop` and shares the app's credentials and config.

---

## Option 4: Build From Source

Requires Rust stable (`rustup update stable`).

```bash
git clone https://github.com/superhumancorp/r2drop.git
cd r2drop
./scripts/install-cli.sh --prefix ~/.local
```

---

## PATH Setup

If `r2drop` is not found after install:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify the install:

```bash
r2drop --version
```

---

## Shared State With the macOS App

The CLI and app share the same local data directory (`~/.r2drop/`):

- `config.toml` — accounts and preferences
- `queue.db` — upload queue
- `history.db` — upload history

Credentials are shared via macOS Keychain (service: `com.superhumancorp.r2drop`).

This means if you configure an account in the macOS app, the CLI can use it immediately — no re-authentication needed.

---

## Next Step

Once installed, [authenticate with Cloudflare](authentication.md) to start uploading.
