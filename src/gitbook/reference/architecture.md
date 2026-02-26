# Architecture

A brief overview of how R2Drop is built — useful for contributors and anyone curious about what happens under the hood.

---

## Components

```
R2Drop
├── macOS App (Swift/SwiftUI)
│   ├── Menu bar icon + window (5 tabs)
│   ├── Finder Sync Extension (right-click menu)
│   └── App Groups (shared SQLite with extension)
│
├── Upload Engine (Rust)
│   ├── r2-core — S3 client, multipart logic, queue, history
│   ├── r2-ffi  — C FFI bridge (Swift calls into Rust)
│   └── r2-cli  — Standalone CLI binary
│
└── Local Data (~/.r2drop/)
    ├── config.toml — accounts + preferences
    ├── queue.db    — upload queue (SQLite)
    ├── history.db  — upload history (SQLite)
    └── r2drop.sock — IPC socket (CLI ↔ app)
```

---

## Upload Flow

1. User triggers an upload (Finder, drag-drop, CLI, deep link)
2. Upload is added to `queue.db` with status `pending`
3. The Rust engine picks it up and begins a multipart S3 upload directly to Cloudflare R2
4. Progress is written back to `queue.db` in real time
5. On completion, the entry moves to `history.db` and the public URL is returned
6. The app copies the URL to the clipboard and fires a macOS notification

Files go **directly from your Mac to Cloudflare R2**. R2Drop's servers are never in the data path.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | Swift + SwiftUI (macOS 13+) |
| Upload engine | Rust (tokio async, aws-sdk-s3) |
| FFI | Rust `staticlib` + `cbindgen` → C header → Swift |
| Database | SQLite via `rusqlite` |
| Config | TOML (`~/.r2drop/config.toml`) |
| Credentials | macOS Keychain (`Security.framework`) |
| IPC | Unix socket (`r2drop.sock`) + shared SQLite via App Groups |
| Auto-updates | Sparkle framework |
| Distribution | `.dmg` + Homebrew Cask |
| CI/CD | GitHub Actions |

---

## Security Model

- **No R2Drop servers in the data path** — files go directly to Cloudflare R2
- **Keychain-only credentials** — API tokens never written to disk or config files
- **Least-privilege token design** — users are guided to create tokens scoped to specific R2 buckets
- **Open source** — every network call the app makes is auditable at [github.com/superhumancorp/r2drop](https://github.com/superhumancorp/r2drop)

---

## Finder Sync Extension

The right-click *Send to R2* menu item is implemented as a macOS Finder Sync Extension.

The extension communicates with the main app via **App Groups shared SQLite** (not XPC). This approach is simpler and avoids XPC permission complexities.

App Group identifier: `group.com.superhumancorp.r2drop`

---

## CI/CD Pipelines

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| `ci.yml` | Push/PR to `main` | Build + lint |
| `release.yml` | Tag `v*` | Sign, notarize, publish `.dmg`, bump Homebrew tap |
| `cli-release.yml` | Tag `v*` | Cross-compile CLI (macOS + Linux, arm64 + x86_64) |
| `deploy-www.yml` | Push to `src/www/` | Deploy website to Cloudflare Pages |
