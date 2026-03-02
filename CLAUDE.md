# CLAUDE.md — R2Drop Agent Context

> **Self-updating document.** Update this file whenever you learn something new about the codebase, discover a pattern, fix a non-obvious bug, or make an architectural decision. This file is your persistent memory across sessions.

## Project Intent

R2Drop is a native macOS menu bar application for uploading files and folders to Cloudflare R2 storage. Users right-click files in Finder → "Send to R2" and the app handles multipart, parallel, resumable uploads. The project is open source (MIT) and models itself after the Tailscale macOS experience: minimal UI, reliable background operation, zero friction.

The companion CLI (`r2-cli`) shares the same Rust upload engine and config, enabling headless/terminal use on macOS (Apple Silicon and Intel).

## Repo Layout

```
r2drop/                           # Monorepo root
├── CLAUDE.md                     # ← You are here. Keep this updated.
├── R2Drop-Requirements.md        # Authoritative PRD (FR-001 through FR-068)
├── art/                          # Brand assets (SVG, PNG, PSD)
├── docs/                         # GitBook documentation (future)
└── src/
    ├── app/                      # Xcode workspace root
    │   ├── R2Drop.xcworkspace/   # Open this in Xcode
    │   ├── R2Drop/               # Xcode project
    │   │   ├── App/              # SwiftUI menu bar app
    │   │   └── FinderExtension/  # Finder Sync Extension target
    │   ├── Packages/
    │   │   ├── R2Core/           # Swift package: models, config, queue, history
    │   │   └── R2Bridge/         # Swift package: FFI wrapper around Rust
    │   ├── engine/               # Rust workspace
    │   │   ├── r2-core/          # Shared upload logic, S3 client
    │   │   ├── r2-ffi/           # C FFI bridge (staticlib + cbindgen)
    │   │   └── r2-cli/           # Standalone CLI binary
    │   ├── scripts/
    │   │   ├── build-rust.sh     # Compile Rust → .a + .h
    │   │   ├── install-cli.sh
    │   │   └── generate-dmg.sh
    │   └── .github/workflows/
    │       ├── ci.yml            # PR: lint, build, test
    │       ├── release.yml       # Release: sign, notarize, publish .dmg
    │       └── cli-release.yml   # Cross-compile CLI binaries
    └── www/                      # Marketing website (deferred, gitignored)
```

## Tech Stack

- **UI:** Swift + SwiftUI (macOS 13+, menu bar app)
- **Upload engine:** Rust (async, tokio, aws-sdk-s3)
- **FFI:** Rust `staticlib` + `cbindgen` → C header → Swift via R2Bridge package
- **Database:** SQLite (`rusqlite`) for queue.db and history.db
- **Config:** TOML at `~/.r2drop/config.toml`
- **Credentials:** macOS Keychain (`Security.framework`), service: `com.superhumancorp.r2drop`
- **IPC:** App Groups (`group.com.superhumancorp.r2drop`) + shared SQLite
- **Auto-updates:** Sparkle framework (Ed25519 key: `NWlOpvs7+ccCaW6557MqyCO94w3KVziS7uAOOxR8gQk=`)
- **CI/CD:** GitHub Actions
- **Distribution:** .dmg from GitHub Releases (Homebrew tap at github.com/superhumancorp/homebrew-tap)

## Credentials & Secrets

**NEVER commit secrets. All paths below are gitignored.**

| Location | Contents |
|----------|----------|
| `src/app/.env` | CF_API_TOKEN, GITHUB_TOKEN, APPLE_CERTIFICATE_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_TEAM_ID, APPLE_ID (email), APPLE_APP_SPECIFIC_PASSWORD |
| `src/app/credentials/` | Apple .cer files, CSR, provisioning profiles |
| GitHub Actions Secrets | Mirror of .env values — pushed via API |

**Runtime credentials** (user's R2 tokens) are stored exclusively in macOS Keychain. The config.toml contains account metadata (bucket names, endpoints) but **never** tokens or secrets.

## Local Data Directory

```
~/.r2drop/
├── config.toml       # Accounts, preferences (NO secrets)
├── queue.db          # Upload queue (SQLite)
├── history.db        # Upload history (SQLite)
├── r2drop.sock       # Unix socket for CLI ↔ app IPC
└── logs/
    └── r2drop.log    # Rolling log files
```

## Key Architectural Decisions

- **Upload-only:** No download, sync, or browsing of bucket contents (P0 scope)
- **No Cloudflare OAuth:** Cloudflare doesn't support third-party desktop OAuth. Auth is a guided one-time token paste → Keychain storage flow.
- **Finder Sync Extension** communicates with the main app via App Groups shared SQLite — not XPC
- **TOML config** shared between macOS app and CLI so both read `~/.r2drop/config.toml`
- **Rust staticlib** (not dylib) — single binary, no runtime dependencies
- **Developer ID Application** cert required (not Apple Distribution) for outside-App-Store distribution

## Build Commands

```bash
# Build Rust engine (from src/app/)
./scripts/build-rust.sh

# Open in Xcode
open src/app/R2Drop.xcworkspace

# Install CLI locally
./scripts/install-cli.sh

# Package .dmg
./scripts/generate-dmg.sh
```

## Known Issues & Gotchas

- Apple cert .p12 export requires the private key to be in the same Keychain as the certificate. If you regenerate certs, use `openssl genrsa` + `openssl req` to create the CSR so you control the private key, then combine with `openssl pkcs12 -export`.
- The `.p12` password and APPLE_ID (email, not bundle ID) are both needed for notarization in CI.
- Sparkle requires the Ed25519 public key in Info.plist under `SUPublicEDKey`.

## Self-Update Instructions

**When to update this file:**
- You discover a new pattern or convention in the codebase
- You fix a bug whose root cause was non-obvious
- You make an architectural decision or trade-off
- You add a new dependency, script, or workflow
- You learn something about the build process, CI, or Apple signing
- A section below becomes stale or incorrect

**How to update:**
1. Read this file at the start of each session
2. As you work, note anything that would help future sessions
3. Before ending, append or edit relevant sections
4. Keep entries concise — this is a reference, not a journal

## Session Log

<!-- Append dated entries as you learn things. Most recent first. -->

### 2026-02-27
- Full documentation audit against codebase. Fixed inaccuracies in gitbook docs, README.md, and CLAUDE.md.
- Key fixes: exclusion patterns list was wrong (.Trashes not __Trashes, removed .env not in defaults), company name corrected to "Superhuman Intelligence LLC", CLI is macOS-only (not Linux/Windows), Homebrew tap marked as "coming soon" (not yet published), app installs CLI to /usr/local/bin (not ~/.local/bin), added missing config fields (exclusion_patterns, allow_anonymous_telemetry) to reference docs, fixed telemetry from "opt-in" to "on by default, opt-out", fixed email domain from r2drop.app to r2drop.com, added S3 credential derivation (SHA-256) to architecture docs, fixed automation script JSON field names.

### 2026-02-23
- Initial CLAUDE.md created
- Resolved Apple cert .p12 export issue: private key wasn't in Keychain because CSR was generated elsewhere. Fixed by generating key with `openssl genrsa`, creating CSR with `openssl req`, getting new cert from Apple, and combining with `openssl pkcs12 -export`.
- All 5 GitHub Actions secrets now pushed: APPLE_CERTIFICATE_BASE64, APPLE_CERTIFICATE_PASSWORD, APPLE_TEAM_ID, APPLE_ID ([REDACTED]), APPLE_APP_SPECIFIC_PASSWORD
- Fixed APPLE_ID from bundle ID (com.superhumancorp.r2drop) to email ([REDACTED]) for notarization
