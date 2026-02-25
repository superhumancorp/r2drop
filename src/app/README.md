<p align="center">
  <img src="../../art/banner.png" alt="R2Drop banner" width="100%" />
</p>

<h1 align="center">R2Drop</h1>

<p align="center">A polished macOS uploader for Cloudflare R2 with Finder, menu bar, Dock, and CLI workflows.</p>

<p align="center">
  <!-- Replace APP_STORE_URL, HOMEBREW_URL, and QUICK_INSTALL_URL with your production links -->
  <a href="https://apps.apple.com/app/idYOUR_APP_ID">
    <img alt="Mac App Store" src="https://img.shields.io/badge/Mac%20App%20Store-Download-111111?logo=apple&logoColor=white" />
  </a>
  <a href="https://brew.sh">
    <img alt="Homebrew" src="https://img.shields.io/badge/Homebrew-CLI-FBB040?logo=homebrew&logoColor=111111" />
  </a>
  <a href="https://example.com/install.sh">
    <img alt="Quick Install" src="https://img.shields.io/badge/Quick%20Install-curl%20%7C%20bash-0f172a?logo=gnubash&logoColor=white" />
  </a>
</p>

## What R2Drop Is

R2Drop makes Cloudflare R2 uploads feel native on macOS.

Instead of switching to dashboards and copying links manually, you can send files and folders to R2 directly from Finder, the menu bar, or the Dock and let R2Drop handle queueing, retries, notifications, and URL generation.

## Why It Exists

Uploading to R2 is often slower than it should be.

- Too much context switching (Finder -> browser -> dashboard -> bucket -> upload)
- Repetitive manual steps for common workflows
- No native queue/progress UX for day-to-day desktop work
- Friction when working across multiple accounts/buckets

R2Drop fixes that with a native macOS workflow and a matching CLI.

## Strong Selling Points

- Native macOS workflow for Cloudflare R2 (not a web wrapper)
- Multiple upload entry points: Finder, menu bar, Dock, file picker, and deep links
- Upload files and folders (including recursive folder handling)
- Background queue with progress, retries, pause/resume/cancel controls
- Multi-account support with active account switching
- Bucket + path prefix routing per account
- Public URL copy flow with custom domain support
- Notifications for success, failures, and token expiry
- Optional CLI companion (`r2drop`) for terminal and automation
- Anonymous telemetry controls (can be disabled in onboarding/settings)

## Upload Entry Points (Implemented)

R2Drop supports all of these today:

1. Finder right-click: `Send to R2`
2. Drag files/folders onto the menu bar icon
3. Drag files/folders onto the Dock icon (when Dock icon is visible)
4. Menu bar dropdown: `Upload File(s)...` (supports files and directories in one picker)
5. Queue tab drag-and-drop in Settings UI
6. Deep links (`r2drop://...`) for automation and app actions

## Install

### macOS App

Use the Mac App Store badge above (replace the placeholder link with your production App Store URL).

Example badge link format:

```md
[![Mac App Store](https://img.shields.io/badge/Mac%20App%20Store-Download-111111?logo=apple&logoColor=white)](https://apps.apple.com/app/idYOUR_APP_ID)
```

### CLI (`r2drop`)

R2Drop includes a CLI companion for terminal workflows and automation.

1. Homebrew (assumed available)

```bash
brew install r2drop
```

2. Quick install (assumed available)

```bash
curl -fsSL https://example.com/install.sh | bash
```

3. From the macOS app

- Open `Preferences...`
- Use the CLI install action in Settings
- The app installs the binary into `~/.local/bin` when possible

See `CLI.md` for full CLI usage.

## Quick Start (macOS App)

1. Launch R2Drop.
2. Complete onboarding (paste a Cloudflare API token, select/create a bucket, and optionally set a path prefix/custom domain).
3. Upload something using Finder right-click or drag-and-drop.
4. Copy the generated URL from the notification or queue/history UI.

## How Uploads Work

R2Drop is designed for repeated day-to-day uploads, not one-off demos.

- Files/folders are queued locally before upload begins
- Background processing handles upload execution and retries
- The queue and upload history are persisted locally
- Finder extension jobs are transferred through an App Group shared queue
- Notifications include actions like copy URL and retry where applicable

## Multi-Account + URL Workflows

R2Drop supports multiple Cloudflare accounts and lets you switch the active account from the menu bar.

Per account you can configure:

- Bucket
- Default path prefix
- Optional custom domain for generated URLs

That makes it easy to separate environments, clients, or projects while keeping a fast upload flow.

## CLI Companion

The `r2drop` CLI shares the same product goal: fast uploads to Cloudflare R2 without dashboard friction.

Highlights:

- `r2drop login` (interactive or scripted)
- `r2drop upload <path>` for files or folders
- `r2drop status` and `r2drop queue`
- `r2drop accounts` management
- `r2drop config get/set`
- `r2drop history` browsing/search
- JSON output options for automation

Full docs: `CLI.md`

## Privacy, Telemetry, and Logging

R2Drop includes anonymous telemetry support (PostHog) with a user-facing toggle in onboarding and settings.

- Telemetry can be disabled
- Sensitive values are sanitized/hashed before tracking
- Error tracking is rate-limited/deduplicated to reduce analytics spam

Implementation plan and event catalog: `INSTRUMENTATION.md`

R2Drop also writes local rotating logs under `~/.r2drop/logs/`.

## Troubleshooting

### Finder right-click item is missing

Finder Sync extensions are cached aggressively.

1. Open `System Settings > Privacy & Security > Extensions > Finder Extensions`
2. Toggle the R2Drop Finder extension off/on
3. Restart Finder:

```bash
killall Finder
```

### `r2drop` command not found after CLI install

If the CLI was installed to `~/.local/bin`, make sure it is on your `PATH`.

For `zsh`:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Project Docs

- `CLI.md` — CLI reference and examples
- `INSTRUMENTATION.md` — PostHog instrumentation strategy and event catalog
- `TODO.md` — reviewed implementation checklist / remaining work
