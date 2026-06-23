# Roadmap

Current status and planned features for R2Drop. Check marks indicate shipped features.

Have a feature request? [Submit it on Canny](https://superhuman.canny.io/) or open a PR — contributions welcome.

---

## Core App

- [x] Native macOS menu bar app (Swift + SwiftUI)
- [x] Finder right-click "Send to R2" via Finder Sync Extension
- [x] Drag and drop files onto menu bar icon
- [x] File picker from menu bar
- [x] Dock icon file drop
- [x] Deep link support (`r2drop://upload`, `r2drop://preferences`, etc.)
- [x] Background upload queue with progress tracking
- [x] Pause, resume, and cancel uploads
- [x] Parallel uploads (configurable concurrency)
- [x] Configurable chunk size
- [x] Conflict resolution (overwrite / skip / rename)
- [x] File exclusion filters (`.DS_Store`, `._*`, etc.)
- [x] Offline queueing with auto-resume on reconnect
- [x] Upload history with search
- [x] macOS notifications (success, failure, token expiry)
- [x] Dark mode support
- [x] Sparkle auto-updates

## Accounts & Security

- [x] Multi-account support with one-click switching
- [x] Guided onboarding wizard (5-panel setup flow)
- [x] Cloudflare API token validation
- [x] macOS Keychain credential storage (never on disk)
- [x] Per-account bucket and path prefix config
- [x] Custom domain support for public URLs
- [x] Auto-copy public URL to clipboard after upload
- [x] Background token health checks

## Upload Engine

- [x] Rust-based upload engine (multipart, parallel)
- [x] S3-compatible Cloudflare R2 API
- [x] SQLite persistent queue (crash-resilient)
- [x] Retry with exponential backoff
- [x] Folder uploads across all entry points

## CLI

- [x] `r2drop upload` — upload files and folders
- [x] `r2drop login` — interactive token setup
- [x] `r2drop status` — daemon and connectivity check
- [x] `r2drop accounts` — manage accounts
- [x] `r2drop queue` — view upload queue
- [x] `r2drop history` — browse upload history
- [x] `r2drop config` — get/set configuration
- [x] `--json` output for scripting
- [x] Shared config with macOS app (`~/.r2drop/`)

## Analytics

- [x] PostHog anonymous telemetry (opt-out in Settings)
- [x] Structured event catalog with sanitized properties
- [x] Rate limiting and error aggregation
- [x] Privacy-first: all identifiers hashed, no PII collected

## Distribution

- [x] `.dmg` download from GitHub Releases
- [x] Code signing + Apple notarization
- [x] Homebrew tap (`brew tap superhumancorp/tap`)
- [x] `curl | bash` installer for CLI
- [x] CI/CD: build, sign, notarize, publish on tag push
- [x] Website at [r2drop.com](https://r2drop.com)

## Settings

- [x] Hide Dock icon (menu-bar-only mode)
- [x] Launch at Login
- [x] Sound on upload complete
- [x] Concurrent uploads (1–16)
- [x] Chunk size (5–100 MB)
- [x] File exclusion patterns
- [x] Install CLI from Settings
- [x] Telemetry opt-out toggle

---

## Future

These are planned but not yet shipped. PRs welcome.

- [ ] Interrupt in-flight uploads on pause/cancel (small uploads currently finish before pause takes effect)
- [ ] Conflict check timeout UX (explicit handling when HEAD request times out)
- [ ] Bundle prebuilt CLI binary in `.dmg` (currently requires repo checkout for "Install CLI")
- [ ] First CLI release with GitHub Release binaries
- [ ] Homebrew Cask and Formula end-to-end validation
- [ ] Finder badge overlays on uploaded files
- [ ] R2 bucket browser / file download
- [ ] Client-side encryption before upload
- [ ] File size warnings (configurable threshold)
- [ ] Global upload hotkey
- [ ] Cross-platform CLI releases (Linux + Windows)
- [ ] Mac App Store submission

---

[Submit feedback](https://superhuman.canny.io/) · [Open an issue](https://github.com/superhumancorp/r2drop/issues) · [View on GitHub](https://github.com/superhumancorp/r2drop)
