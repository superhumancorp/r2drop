# Installation

R2Drop has two components: the **macOS app** (menu bar, Finder extension, upload UI) and the **CLI** (`r2drop` command).

You can use either or both — they share the same config and credentials.

---

## macOS App

### Direct Download (Recommended)

Download the latest `.dmg` from [GitHub Releases](https://github.com/superhumancorp/r2drop/releases).

1. Open the `.dmg` file
2. Drag **R2Drop** to your Applications folder
3. Launch R2Drop — the menu bar icon appears
4. Complete the [onboarding flow](first-upload.md) to connect your Cloudflare account

### Homebrew Cask (Coming Soon)

The Homebrew tap is not yet published. For now, use the direct `.dmg` download above.

```bash
brew tap superhumancorp/tap
brew install --cask superhumancorp/tap/r2drop
```

---

## CLI (`r2drop`)

The CLI lets you upload files from your terminal, automate uploads in scripts, and use R2Drop in CI pipelines.

### Option 1: Homebrew (Coming Soon)

The Homebrew tap is not yet published. For now, use the quick install script or build from source.

```bash
brew tap superhumancorp/tap
brew install --formula superhumancorp/tap/r2drop
```

### Option 2: Quick Install Script

```bash
curl -fsSL https://r2drop.com/install.sh | bash
```

This installs the `r2drop` binary to `~/.local/bin`.

### Option 3: From the macOS App

If you already have the app installed, open **Settings → Command Line Interface** and click **Install CLI**.

<figure><img src="https://cdn.r2drop.com/screenshot-6.png" alt="Settings tab showing CLI install button"></figure>

The app installs `r2drop` to `/usr/local/bin/r2drop`.

### Option 4: Build From Source

```bash
git clone https://github.com/superhumancorp/r2drop.git
cd r2drop
./scripts/install-cli.sh --prefix ~/.local
```

Requires a Rust stable toolchain (`rustup update stable`).

---

## PATH Setup

If you installed the CLI to `~/.local/bin` and the `r2drop` command is not found:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

---

## System Requirements

| Component | Requirement |
|-----------|-------------|
| macOS app | macOS 13 Ventura or later |
| CLI | macOS 10.15+ (Apple Silicon and Intel) |

---

## Next Step

Once installed, [set up your first account](first-upload.md) to connect R2Drop to your Cloudflare R2 bucket.
