# R2Drop for macOS — Product Requirements Document

> **Product:** R2Drop — A native macOS menu bar app for uploading files to Cloudflare R2
> **Company:** Superhuman Corp
> **License:** Open Source (MIT)
> **Version:** PRD v1.2
> **Date:** February 23, 2026
> **Scope:** P0 — Minimum Viable Product

---

## 1. Overview

R2Drop is a native macOS menu bar application that lets users upload files and folders to Cloudflare R2 storage via a right-click Finder context menu. It prioritizes simplicity, reliability, and performance — modeled after the Tailscale macOS experience.

The project is open source. The monorepo contains the macOS app (Swift + SwiftUI) and a cross-platform CLI tool (Rust). A marketing/docs website at `r2drop.com` is deferred to a future milestone.

---

## 2. Architecture

### 2.1 Current Repository State

The repo already exists at `https://github.com/superhumancorp/r2drop.git` with the following structure. The macOS app lives in `src/app/` and the marketing website in `src/www/` (gitignored for now — deferred to a future milestone).

```
r2drop/                              # Monorepo root
├── art/                             # Brand assets
│   ├── icon-flat.svg
│   ├── icon-flat.png
│   ├── r2-drop-logo.psd
│   └── r2-logo.png
├── docs/                            # GitBook documentation (future)
│   └── .gitkeep
├── src/
│   ├── app/                         # macOS app + CLI (Xcode workspace root)
│   │   ├── .env                     # Environment variables (gitignored) — see §2.5
│   │   ├── .gitignore               # Ignores credentials/, .env, and ../www/
│   │   ├── AGENTS.md                # Agent workflow instructions (beads/bd)
│   │   ├── credentials/             # Apple certs & profiles (gitignored) — see §2.5
│   │   │   ├── development.cer
│   │   │   ├── distribution.cer
│   │   │   ├── CertificateSigningRequest.certSigningRequest
│   │   │   ├── R2Drop_MacOS_Development.provisionprofile
│   │   │   ├── R2Drop_Distribution.provisionprofile
│   │   │   └── R2Drop_Development.mobileprovision
│   │   ├── R2Drop.xcworkspace/      # Xcode workspace (entry point)
│   │   ├── .ralph-tui/              # Agent config (ralph-tui)
│   │   ├── .claude/                 # Agent config (claude)
│   │   └── .beads/                  # Issue tracking (bd/beads)
│   └── www/                         # Marketing website (gitignored, deferred)
│       ├── index.html
│       ├── privacy-policy.html
│       ├── terms-of-services.html
│       └── ...
└── R2Drop-Requirements.md           # This document
```

### 2.2 Target Repository Structure

The agent should scaffold the following structure within `src/app/`. The Xcode workspace already exists — the agent adds targets, packages, and the Rust engine.

```
src/app/
├── .env                             # EXISTING — env vars (gitignored)
├── .gitignore                       # EXISTING — ignores credentials/, .env
├── AGENTS.md                        # EXISTING — agent workflow instructions
├── credentials/                     # EXISTING — Apple certs (gitignored)
├── R2Drop.xcworkspace/              # EXISTING — Xcode workspace
├── R2Drop/                          # NEW — Xcode project
│   ├── R2Drop.xcodeproj
│   ├── App/                         # Main menu bar app target (SwiftUI)
│   │   ├── AppDelegate.swift        # NSApplicationDelegate, deep link handler, URL scheme
│   │   ├── MenuBarController.swift  # NSStatusItem, icon, dropdown menu, drag-and-drop
│   │   ├── KeychainManager.swift    # Wrapper around Security.framework Keychain Services
│   │   ├── Views/
│   │   │   ├── Onboarding/
│   │   │   │   ├── OnboardingCarousel.swift  # 5-panel carousel container + dot indicators
│   │   │   │   ├── WelcomePanel.swift        # Panel 1: hero, icon, feature pills
│   │   │   │   ├── HowItWorksPanel.swift     # Panel 2: 3-step education
│   │   │   │   ├── TokenSetupPanel.swift     # Panel 3: open CF dashboard + guide
│   │   │   │   ├── TokenPastePanel.swift     # Panel 4: paste + validate + Keychain store
│   │   │   │   └── BucketPickerPanel.swift   # Panel 5: bucket select + path + done
│   │   │   ├── PreferencesWindow.swift
│   │   │   ├── QueueTab.swift
│   │   │   ├── AccountsTab.swift
│   │   │   ├── SettingsTab.swift
│   │   │   ├── HistoryTab.swift
│   │   │   ├── AboutTab.swift
│   │   │   └── ConfirmationDialog.swift
│   │   ├── Info.plist               # URL scheme: r2drop://, app metadata
│   │   └── R2Drop.entitlements      # Keychain access, App Groups, network client
│   ├── FinderExtension/             # Finder Sync Extension target
│   │   ├── FinderSync.swift         # Right-click "Send to R2" context menu handler
│   │   ├── Info.plist
│   │   └── FinderExtension.entitlements  # App Groups (shared IPC with main app)
│   └── Assets.xcassets              # App icon, menu bar icons (static + animated frames)
├── Packages/                        # Swift Packages (shared logic)
│   ├── R2Core/                      # Models, config, queue, history, account management
│   │   ├── Package.swift
│   │   └── Sources/R2Core/
│   │       ├── Config.swift         # TOML config read/write (~/.r2drop/config.toml)
│   │       ├── QueueManager.swift   # SQLite queue CRUD + status transitions
│   │       ├── HistoryManager.swift # SQLite upload history
│   │       ├── AccountManager.swift # Multi-account CRUD, active account switching
│   │       └── Models/
│   │           ├── Account.swift
│   │           ├── UploadJob.swift
│   │           └── HistoryEntry.swift
│   └── R2Bridge/                    # Swift wrapper around Rust FFI
│       ├── Package.swift
│       └── Sources/R2Bridge/
│           ├── R2Client.swift       # Swift-friendly async API over C FFI
│           └── FFI/                 # Generated C headers from cbindgen
├── engine/                          # Rust workspace
│   ├── Cargo.toml                   # Workspace members: r2-core, r2-ffi, r2-cli
│   ├── r2-core/                     # Shared upload logic, S3 client, hashing, queue
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs
│   │       ├── upload.rs            # Multipart upload engine with resume + retry
│   │       ├── s3.rs                # S3-compatible R2 client (ListBuckets, PutObject, etc.)
│   │       ├── queue.rs             # SQLite queue persistence layer
│   │       ├── hash.rs              # SHA-256 / ETag content hashing for idempotency
│   │       └── config.rs            # TOML config parsing + writing
│   ├── r2-ffi/                      # C FFI bridge for Swift interop
│   │   ├── Cargo.toml               # crate-type = ["staticlib"]
│   │   ├── src/lib.rs               # extern "C" fn wrappers
│   │   ├── build.rs                 # cbindgen: generates r2_ffi.h
│   │   └── r2_ffi.h                 # Generated C header (checked in for Xcode)
│   └── r2-cli/                      # Standalone cross-platform CLI binary
│       ├── Cargo.toml
│       └── src/
│           ├── main.rs              # CLI entry point (clap)
│           ├── commands/
│           │   ├── upload.rs
│           │   ├── login.rs         # Token setup flow + Keychain storage
│           │   ├── status.rs
│           │   ├── accounts.rs
│           │   ├── config.rs
│           │   └── history.rs
│           └── output.rs            # JSON / human-readable output formatting
├── scripts/
│   ├── build-rust.sh                # Compile Rust → .a static lib + .h header
│   ├── install-cli.sh               # Install r2drop CLI to /usr/local/bin
│   └── generate-dmg.sh              # Package signed .app into .dmg
└── .github/
    └── workflows/
        ├── ci.yml                   # Lint + build + test on PR
        ├── release.yml              # Build, sign, notarize, publish .dmg to GitHub Releases
        └── cli-release.yml          # Cross-compile CLI for macOS/Linux/Windows
```

### 2.3 Tech Stack

| Component | Technology | Rationale |
|---|---|---|
| UI Layer | Swift + SwiftUI | Native macOS menu bar, preferences window, Finder Sync Extension |
| Upload Engine | Rust (`r2-core`) | High-performance async I/O, memory safety, shared with CLI |
| FFI Bridge | Rust `staticlib` + `cbindgen` → Swift C interop | Zero-overhead bridge between SwiftUI and Rust engine |
| CLI | Rust (`r2-cli`, depends on `r2-core`) | Single binary, cross-platform (macOS/Linux/Windows) |
| Local Database | SQLite via `rusqlite` | Queue + history persistence, crash-resilient |
| Config | TOML (`~/.r2drop/config.toml`) | Human-readable, standard in Rust ecosystem, easy to hand-edit |
| Credentials | macOS Keychain via `Security.framework` | OS-level encryption, never in plaintext on disk |
| Finder Integration | Finder Sync Extension | Proper Apple API for context menu + badge overlays |
| IPC (App ↔ Extension) | App Groups + shared SQLite | Extension writes to queue.db, app processes it |
| Auto-Updates | Sparkle framework | Industry standard for macOS apps outside App Store |
| CI/CD | GitHub Actions | Build, test, sign, notarize, publish to GitHub Releases |
| Distribution | `.dmg` + Homebrew Cask | Standard macOS distribution channels |

### 2.4 Local Data Directory

All app and CLI state lives in a shared directory. Default: `~/.r2drop/`. Overridable via Settings tab or `R2DROP_HOME` env var.

```
~/.r2drop/
├── config.toml       # Accounts, preferences, settings (NO secrets — those are in Keychain)
├── queue.db          # SQLite — active upload queue
├── history.db        # SQLite — completed upload history
└── logs/             # Rolling log files, configurable retention
    ├── r2drop.log
    └── r2drop.log.1
```

### 2.5 Credential & Secret Management

**Developer credentials** (gitignored, never committed):

| File | Location | Contents |
|---|---|---|
| `.env` | `src/app/.env` | `CF_API_TOKEN`, `CF_DOMAIN`, `GITHUB_TOKEN`, `GITHUB_REPO`, `MACOS_APP_ID_DEVELOPMENT`, `MACOS_APP_ID_DISTRIBUTION`, `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` |
| `credentials/` | `src/app/credentials/` | Apple Developer certificates (`.cer`), provisioning profiles (`.provisionprofile`, `.mobileprovision`), CSR |

Both `.env` and `credentials/` are listed in `src/app/.gitignore` and must never be committed. `src/www/` is also gitignored (deferred to a future milestone). CI/CD accesses secrets via GitHub repository secrets (see §8).

**User credentials** (runtime):

All user-facing R2 API tokens (Access Key ID + Secret Access Key) are stored exclusively in the macOS Keychain via `Security.framework` (`SecItemAdd` / `SecItemCopyMatching`). The Keychain service name is `com.superhumancorp.r2drop`. Each account's credentials are stored as a separate Keychain item keyed by account name. The `config.toml` file contains account metadata (name, bucket, path, custom domain) but **never** contains secrets.

### 2.6 IPC & Process Model

The macOS app runs as the primary process. The Finder Sync Extension communicates via App Groups (`group.com.superhumancorp.r2drop`) — it writes `UploadJob` records to the shared `queue.db`, and the app's queue manager polls and processes them. The CLI communicates with the running app daemon via a Unix domain socket at `~/.r2drop/r2drop.sock`. If the app isn't running, the CLI operates standalone using `r2-core` directly.

---

## 3. Functional Requirements — P0

### 3.1 Authentication — Guided Token Setup

Cloudflare does not offer application-scoped OAuth for third-party desktop apps. R2Drop uses a guided token creation flow that makes the one-time setup as frictionless as possible, then stores the token in the OS Keychain so the user never sees it again.

#### 3.1.1 Onboarding Flow (First Launch)

The onboarding is a **5-panel carousel** presented in a clean, centered window (~520×400pt). Each panel slides left-to-right with a smooth `easeInOut` transition. A row of dot indicators at the bottom shows progress. Every panel has a "Continue" button at the bottom-right, except the final panel which has "Done".

**Panel 1 — Welcome** (hero panel)
- R2Drop app icon (large, centered, subtle bounce animation on appear)
- Headline: "R2Drop"
- Subheadline: "Upload files to Cloudflare R2 right from your Finder."
- Three feature pills below (icon + short text, horizontal row):
  - "Right-click to upload"
  - "Blazing fast"
  - "Open source"
- "Continue" button

**Panel 2 — How It Works** (education panel)
- Three vertically stacked steps with icons and one-line descriptions:
  1. "Right-click any file in Finder → Send to R2"
  2. "R2Drop uploads it to your Cloudflare bucket"
  3. "The URL is copied to your clipboard — done"
- A small animated illustration or Lottie showing the right-click → upload → clipboard flow (static fallback: 3 step icons with arrows between them)
- "Continue" button

**Panel 3 — Create Your R2 Token** (action panel)
- Friendly copy: "R2Drop needs a Cloudflare API token with R2 read/write access. We'll open Cloudflare for you — it takes about 30 seconds."
- A prominent "Open Cloudflare Dashboard" button opens the user's default browser to: `https://dash.cloudflare.com/profile/api-tokens?permissionGroupKeys=[{"key":"workers_r2_storage","type":"edit"}]&name=R2Drop`
- If the pre-filled URL doesn't land on a pre-populated form (Cloudflare may not support query params), fall back to: `https://dash.cloudflare.com/profile/api-tokens` with inline instructions below the button.
- Below the button, a collapsible "Step-by-step guide" disclosure group shows:
  1. Click "Create Token"
  2. Scroll down and click "Create Custom Token" (or use the "Edit Cloudflare Workers" template and modify)
  3. Set token name to "R2Drop"
  4. Under Permissions, select: **Account** → **Workers R2 Storage** → **Edit**
  5. (Optional) Under Account Resources, scope to a specific account if you have multiple
  6. Click "Continue to summary" → "Create Token"
  7. Copy the token value (you'll only see it once)
- The step-by-step guide includes annotated screenshots of the Cloudflare dashboard at each step (stored in `Assets.xcassets` as static images).
- "I already have a token" link skips directly to Panel 4.
- "Continue" button (user can proceed and come back to paste later, but the button is labelled "I've copied my token" to signal intent)

**Panel 4 — Paste Your Token** (validation panel)
- A single large text field with placeholder: "Paste your Cloudflare API token here"
- As soon as the user pastes, the app immediately:
  1. Shows a subtle spinner / loading indicator
  2. Calls the Cloudflare API `GET /user/tokens/verify` to validate the token
  3. If valid, calls `GET /accounts` to get the account ID and name
  4. Calls `GET /accounts/{account_id}/r2/buckets` to list available buckets
  5. Replaces the spinner with a green checkmark animation + "Token verified!" message
  6. The "Continue" button enables (disabled until validation passes)
- If invalid, shows a red inline error: "This token doesn't appear to be valid. Please check that you copied the full token." with a "Clear & Try Again" button.
- On success, the token is immediately stored in macOS Keychain (`Security.framework`). The plaintext token is wiped from memory. It never touches disk.
- "Back" text button on the bottom-left to return to Panel 3 if they need to re-create the token.

**Panel 5 — Choose Your Bucket** (configuration panel)
- Dropdown of the user's R2 buckets (fetched in Panel 4).
- "Create New Bucket" button that opens an inline form: bucket name input (validated: lowercase, alphanumeric, hyphens, 3–63 chars) + "Create" button. Calls `PUT /accounts/{account_id}/r2/buckets/{bucket_name}`.
- Default upload path text field (validated: no trailing slashes, valid S3 key chars). Placeholder: `uploads/`
- Optional custom domain field. Placeholder: `cdn.example.com`
- "Done" button completes onboarding. Triggers a brief celebratory animation (confetti or a checkmark burst), then closes the window and activates the menu bar icon.

#### 3.1.1a Onboarding UX Details

- **Keyboard navigation:** Tab moves between fields, Enter triggers "Continue"/"Done", Escape closes the window (with confirmation if mid-flow).
- **Window behavior:** Non-resizable, centered on screen, no title bar chrome (uses `NSWindow.StyleMask.fullSizeContentView` with a custom toolbar area for the dot indicators). The window cannot be minimized — only closed.
- **"Back" navigation:** Panels 2–5 show a "Back" text button on the bottom-left. Panel 1 does not.
- **Skip link:** A small "Skip setup — I'll configure later" link below the dot indicators on Panels 1–3. If clicked, the app launches into the menu bar with no account configured. The Accounts tab in Preferences shows a prominent "Set up your first account" card.
- **Re-onboarding:** If the user skips or if all accounts are removed, opening Preferences → Accounts shows the same "Set up your first account" card which triggers the flow starting from Panel 3 (skipping Welcome and How It Works).
- **Animations:** Use SwiftUI `.transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))` for panel transitions. Keep animations under 300ms. All animations respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`.

#### 3.1.2 Token Validation & Storage

- **FR-001** — On paste, validate the token by calling `GET https://api.cloudflare.com/client/v4/user/tokens/verify` with `Authorization: Bearer <token>`.
- **FR-002** — On success, store the API token in macOS Keychain using `Security.framework` (`SecItemAdd`). Keychain service: `com.superhumancorp.r2drop`, account: the user's Cloudflare account name or ID. Access group: `group.com.superhumancorp.r2drop` (shared with Finder extension).
- **FR-003** — On every app launch, retrieve the token from Keychain silently (`SecItemCopyMatching`). No user interaction required. If the token is missing or Keychain access fails, prompt re-authentication.
- **FR-004** — Periodically verify the token is still valid (e.g., on app launch and every 24 hours) by calling the verify endpoint. If revoked, show a non-intrusive notification: "Your R2Drop token has expired. Click here to set up a new one." Clicking opens the token setup flow (Step 2).
- **FR-005** — Never write the API token to `config.toml`, log files, crash reports, or any file on disk. The Keychain is the sole secret store.

#### 3.1.3 Multi-Account Support

- **FR-006** — Support multiple Cloudflare accounts. Each account has: a display name, an API token (in Keychain), a selected bucket, a default path, and an optional custom domain.
- **FR-007** — "Add Account" triggers the same guided flow (Steps 2–4) without the welcome screen.
- **FR-008** — "Update Token" on an existing account re-opens Step 3 (paste + validate), replacing the old Keychain entry.
- **FR-009** — "Log Out" removes the Keychain entry and account config (with confirmation dialog).

#### 3.1.4 CLI Authentication

- **FR-010** — `r2drop login` opens the Cloudflare API tokens page in the user's default browser (`open https://dash.cloudflare.com/profile/api-tokens`) and prints inline instructions to the terminal matching the Step 2 guide.
- **FR-011** — CLI then prompts: `Paste your API token:` (input is masked/hidden). On paste, validates the token, stores it in the OS keychain (macOS Keychain via `security` CLI tool, Linux `secret-service`, Windows Credential Manager), and confirms success.
- **FR-012** — `r2drop login --token <token>` accepts the token as an argument (for scripting). Validates and stores.
- **FR-013** — If the R2Drop macOS app is running, the CLI can also trigger the auth flow via deep link: `open r2drop://auth/setup` which opens the app's token setup view directly.

### 3.2 Installation

- **FR-014** — Distribute as a `.dmg` with drag-to-Applications install.
- **FR-015** — On first launch, present the onboarding wizard (§3.1.1).
- **FR-016** — After onboarding, the app runs as a menu bar app with optional Dock icon.

### 3.3 Finder Integration — Right-Click Upload

- **FR-017** — Implement as a Finder Sync Extension. Register "Send to R2" in the Finder context menu for all files and folders.
- **FR-018** — Support bulk selection — user selects multiple files/folders, right-clicks, and all are queued.
- **FR-019** — On right-click, show a confirmation dialog with:
  - File/folder name and size
  - "Compress as ZIP" toggle (default: off)
  - "Copy URL to clipboard" toggle (default: on)
  - "Never ask again" checkbox (default: unchecked)
  - Upload / Cancel buttons
- **FR-020** — If "Never ask again" is checked, skip the dialog on future uploads and use the saved toggle preferences.
- **FR-021** — The Finder extension writes an `UploadJob` record to the shared `queue.db`. The main app picks it up and processes it.

### 3.4 Upload Engine

- **FR-022** — Use the S3-compatible API for R2. All uploads use multipart upload.
- **FR-023** — Parallel uploads: default 4 concurrent, user-configurable (1–16).
- **FR-024** — Chunk size: default 8 MB, user-configurable (5 MB–100 MB).
- **FR-025** — Stream files from disk. Never buffer entire files in memory.
- **FR-026** — Idempotent uploads: before uploading, compute SHA-256 of the local file and compare against existing R2 object ETag. Skip if match.
- **FR-027** — Persistent queue: all upload jobs are written to `queue.db` with status (`pending`, `uploading`, `paused`, `completed`, `failed`), byte progress, and multipart upload ID.
- **FR-028** — Resume after crash/restart: on launch, scan `queue.db` for incomplete jobs. Resume multipart uploads from the last successful part using the stored upload ID.
- **FR-029** — Retry failed uploads with exponential backoff (1s, 2s, 4s, 8s... max 60s). Max 10 retries per job.
- **FR-030** — Offline queueing: if no network, jobs remain in `pending`. Automatically resume when connectivity is restored (use `NWPathMonitor`).
- **FR-031** — Handle locked/in-use files: if a file can't be read, mark the job as `failed` with a descriptive error and surface it in the Queue tab.
- **FR-032** — Uploads are scoped to the active account. Credentials, bucket, and path are isolated per account.
- **FR-033** — When "Copy URL to clipboard" is enabled, copy the full object URL after upload completes. If the account has a custom domain configured, use `https://<custom_domain>/<path>/<filename>`. Otherwise, use the R2 public URL format.

### 3.5 Menu Bar

- **FR-034** — Persistent `NSStatusItem` in the macOS menu bar with an R2Drop icon.
- **FR-035** — Icon animates (e.g., rotating arrows or pulsing) when any upload is in progress.
- **FR-036** — Dropdown menu contains:
  - On/Off toggle (enable/disable the upload daemon)
  - Active account name + account switcher submenu
  - "X of Y uploaded" queue summary (if uploads active)
  - "Preferences..." (opens preferences window)
  - "Quit R2Drop"

### 3.6 Preferences Window

#### 3.6.1 Queue Tab (default when uploads active)

- **FR-037** — Scrollable list of active upload jobs, each showing: file name, file size, progress bar, upload speed, status.
- **FR-038** — Aggregate status bar: average upload rate, "Files X of Y" progress.
- **FR-039** — Pause / Resume / Cancel buttons. Cancel shows a confirmation alert.
- **FR-040** — "Browse" button: opens `https://dash.cloudflare.com/<account_id>/r2/default/buckets/<bucket_name>` in the default browser for the active account.

#### 3.6.2 Accounts Tab (default tab)

- **FR-041** — Sidebar: list of configured accounts. Clicking an account shows its details on the right.
- **FR-042** — "Add Account" button below the account list. Opens the guided token setup flow (§3.1.1 Steps 2–4).
- **FR-043** — Account detail panel: editable account name, bucket selector (dropdown, fetched from Cloudflare API), default upload path (validated text field), custom domain URL (optional, e.g., `cdn.example.com`).
- **FR-044** — "Update Token" button opens the token paste + validate flow (§3.1.1 Step 3). "Log Out" button removes the account and Keychain entry (with confirmation).

#### 3.6.3 Settings Tab

- **FR-045** — Toggles:
  - Hide Dock icon (menu-bar-only mode)
  - Launch R2Drop at Login (register as login item)
  - Play system sound on upload complete (default: on — uses `NSSound.beep()` or the system notification sound)
- **FR-046** — "Install CLI" button: copies the `r2drop` binary to `/usr/local/bin` (or user-chosen path). Shows installed version if already present.
- **FR-047** — Global Upload Hotkey: a key recorder field. User clicks "Record", presses a key combination, app captures and saves it. Displays current binding. "Clear" button to remove.
- **FR-048** — Upload Performance:
  - Concurrent uploads slider/stepper (1–16, default 4)
  - Chunk size slider/stepper (5 MB–100 MB, default 8 MB)
- **FR-049** — File Exclusion List: a table of glob patterns. Pre-populated defaults: `.DS_Store`, `._*`, `.Thumbs.db`, `.Spotlight-V100`, `.Trashes`, `__MACOSX`, `.fseventsd`. User can add, edit, remove patterns.
- **FR-050** — Config directory path: text field showing current `~/.r2drop` path. User can change it. Also overridable via `R2DROP_HOME` env var.
- **FR-051** — Symlink handling: toggle between "Follow symlinks" and "Skip symlinks" (default: skip).

#### 3.6.4 Upload History Tab

- **FR-052** — Searchable, scrollable list of completed uploads: file name, file size, upload timestamp, R2 object path/URL.
- **FR-053** — Each entry has a "Copy URL" button that copies the full object URL (using the custom domain if configured for that account, otherwise the R2 public URL).
- **FR-054** — History persisted in `history.db`. No automatic pruning — user can clear history manually.

#### 3.6.5 About Tab

- **FR-055** — R2Drop app icon, "R2Drop for macOS" title, version number (from build info).
- **FR-056** — Links: Privacy Policy → `r2drop.com/privacy`, Terms of Service → `r2drop.com/terms`, Report an Issue → GitHub Issues URL.
- **FR-057** — Copyright: "© 2026 Superhuman Corp. All rights reserved." and trademark notice.
- **FR-058** — Auto-update: "Automatically check for updates" checkbox (default: on). "Check Now" button. "Last checked: [timestamp]" label. Version selector dropdown for manual update targeting.

### 3.7 Deep Links

R2Drop registers the `r2drop://` URL scheme via `Info.plist`. All deep links are handled in `AppDelegate.application(_:open:)`.

| Deep Link | Action |
|---|---|
| `r2drop://upload?path=<absolute_path>` | Queue file for upload. Respects confirmation dialog unless "Never ask again" is set. |
| `r2drop://upload?path=<path>&compress=true` | Queue with ZIP compression enabled. |
| `r2drop://preferences` | Open the preferences window (Accounts tab). |
| `r2drop://preferences/queue` | Open preferences → Queue tab. |
| `r2drop://preferences/accounts` | Open preferences → Accounts tab. |
| `r2drop://preferences/settings` | Open preferences → Settings tab. |
| `r2drop://preferences/history` | Open preferences → Upload History tab. |
| `r2drop://preferences/about` | Open preferences → About tab. |
| `r2drop://account?name=<name>` | Switch to the named account. |
| `r2drop://browse` | Open active account's bucket in Cloudflare dashboard in browser. |
| `r2drop://browse?account=<name>` | Open a specific account's bucket in browser. |
| `r2drop://auth/setup` | Open the token setup wizard (Step 2). Used by CLI to trigger app-based auth. |
| `r2drop://status` | Return health check info (daemon running, R2 connectivity, active account). |

- **FR-059** — Deep links cannot exfiltrate credentials or modify account settings.
- **FR-060** — Upload deep links respect the confirmation dialog (unless "Never ask again") and validate that the path exists and is readable.

### 3.8 Notifications

- **FR-061** — Use `UNUserNotificationCenter` for macOS native notifications.
- **FR-062** — Notify on: upload complete (single file or batch), upload failed (with error summary), upload paused (network lost), token expired (with "Set up new token" action).
- **FR-063** — Play macOS system sound on upload complete if enabled in Settings (FR-045).

### 3.9 Dark Mode

- **FR-064** — All UI respects `NSAppearance` / SwiftUI `colorScheme`. No hardcoded colors. Test in both light and dark mode.

### 3.10 Conflict Resolution

- **FR-065** — When an upload target path already exists in R2, show a dialog: Overwrite / Skip / Rename (appends `-<timestamp>` suffix). Remember choice per session with a "Apply to all" checkbox.

### 3.11 Drag and Drop

- **FR-066** — Support dragging files onto the menu bar icon to trigger an upload. Uses `NSStatusItem` drag-and-drop API. Respects confirmation dialog and active account.

### 3.12 Audit Logging

- **FR-067** — Log all upload activity (start, progress milestones, complete, fail, retry) to `~/.r2drop/logs/`. Rolling log files with configurable max size and retention count.
- **FR-068** — Logs include: timestamp, account, bucket, file path, file size, R2 key, status, error details. Never log API tokens or credentials.

---

## 4. CLI — P0

The CLI binary is `r2drop`, built from the `r2-cli` Rust crate. It shares `r2-core` with the macOS app for identical upload behavior.

### 4.1 Commands

| Command | Description |
|---|---|
| `r2drop login` | Opens `https://dash.cloudflare.com/profile/api-tokens` in browser, prints setup instructions, prompts for token paste (masked input), validates, stores in OS keychain. |
| `r2drop login --token <token>` | Accepts token as argument (for scripting). Validates and stores. |
| `r2drop upload <path> [--compress] [--account <name>]` | Queue a file or folder for upload. |
| `r2drop status` | Show daemon health, R2 connectivity, active account, queue summary. |
| `r2drop accounts` | List configured accounts. `--add`, `--remove`, `--switch` flags. |
| `r2drop config` | Show/edit config. `r2drop config get <key>`, `r2drop config set <key> <value>`. |
| `r2drop history [--json]` | List upload history. Supports `--limit`, `--search`. |
| `r2drop queue` | Show active upload queue with progress. |

### 4.2 Output Modes

- Default: human-readable colored terminal output.
- `--json` flag on any command: structured JSON output for scripting and piping.

### 4.3 Shared State

- CLI reads/writes the same `~/.r2drop/` directory as the app.
- If the app daemon is running, CLI communicates via Unix socket (`~/.r2drop/r2drop.sock`) for real-time queue and status.
- If the app is not running, CLI operates standalone using `r2-core` directly.

### 4.4 Cross-Platform (P1)

- CLI compiles for macOS (ARM + x86), Linux (x86_64 + ARM64), Windows (x86_64).
- Credentials storage: macOS Keychain via `security` CLI, Linux `secret-service` / `keyring`, Windows Credential Manager.
- CI publishes platform binaries alongside GitHub Releases.

---

## 5. CI/CD

### 5.1 `ci.yml` — On Pull Request

- Lint Swift (SwiftLint) and Rust (`cargo clippy`).
- Build the Xcode workspace (`xcodebuild`).
- Build the Rust workspace (`cargo build`).
- Run Rust tests (`cargo test`).
- Run Swift tests (`xcodebuild test`).

### 5.2 `release.yml` — On Git Tag (`v*`)

- Build the macOS app in Release mode.
- Sign with Developer ID certificate (from GitHub secrets).
- Notarize with Apple.
- Package as `.dmg` via `scripts/generate-dmg.sh`.
- Generate Sparkle appcast update entry.
- Publish `.dmg` + appcast to GitHub Releases.

### 5.3 `cli-release.yml` — On Git Tag (`cli-v*`)

- Cross-compile `r2-cli` for macOS (ARM + x86), Linux (x86_64 + ARM64), Windows (x86_64).
- Publish binaries to GitHub Releases.
- Update Homebrew formula (if applicable).

---

## 6. Distribution

- **Primary:** `.dmg` download from GitHub Releases.
- **Secondary:** `brew install --cask r2drop` via Homebrew Cask.
- **CLI:** `brew install r2drop-cli` or direct binary download from GitHub Releases.
- **Auto-updates:** Sparkle framework checks GitHub Releases appcast on configurable interval.
- **Code signing:** Apple Developer ID Application + Installer certificates. Notarized for Gatekeeper.

---

## 7. Resolved Decisions

| # | Decision | Resolution |
|---|---|---|
| 1 | Authentication | No OAuth — Cloudflare doesn't support third-party desktop OAuth. Guided token creation + one-time paste + Keychain storage. |
| 2 | Bucket creation | Yes — app can create new R2 buckets via Cloudflare API |
| 3 | Download support | Upload-only for P0 |
| 4 | Custom domains | Yes — per-account custom domain in Accounts tab, used for clipboard copy |
| 5 | Team sharing | No |
| 6 | File exclusion | User-configurable glob list with sensible macOS defaults |
| 7 | Encryption | Deferred |
| 8 | Cross-platform | macOS-only app. CLI is cross-platform Rust (P1) |
| 9 | License | Open source (MIT) |
| 10 | Telemetry | None |
| 11 | Website | Deferred. Static HTML on Cloudflare Pages at `r2drop.com` |

---

## 8. Developer Setup Prerequisites

These items require manual setup by the developer before the agent can build:

| Prerequisite | Detail |
|---|---|
| **Xcode** | Latest stable from Mac App Store |
| **Rust toolchain** | Install via `rustup`. Agent can handle this. |
| **Apple Developer Program** | Enrolled account ($99/year). Needed for code signing, notarization, Finder extension entitlements. |
| **Developer ID certificates** | Already provisioned in `src/app/credentials/` — `development.cer` and `distribution.cer`. |
| **Provisioning profiles** | Already provisioned in `src/app/credentials/` — `R2Drop_MacOS_Development.provisionprofile`, `R2Drop_Distribution.provisionprofile`, `R2Drop_Development.mobileprovision`. |
| **App IDs** | `com.superhumancorp.r2drop` (app) and `com.superhumancorp.r2drop.finder-extension` (extension). Distribution ID: `A89MU37ZLB.com.superhumancorp.r2drop`. |
| **App Group** | Register `group.com.superhumancorp.r2drop` for IPC between app and Finder extension. |
| **`.env` file** | Already exists at `src/app/.env`. Contains `CF_API_TOKEN`, `CF_DOMAIN`, `GITHUB_TOKEN`, `GITHUB_REPO`, `MACOS_APP_ID_DEVELOPMENT`, `MACOS_APP_ID_DISTRIBUTION`. |
| **GitHub repo** | Exists at `https://github.com/superhumancorp/r2drop.git`. Add CI secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`. |
| **Sparkle EdDSA keys** | Generate key pair for signing updates. See §10 for instructions. Private key stays in Keychain. Public key goes in `Info.plist` as `SUPublicEDKey`. |
| **Cloudflare account** | Already configured. At least one R2 bucket for testing. |

---

## 9. Scope Boundaries

**In scope (P0 — this document):**
Everything described in sections 3–6.

**Deferred (future milestones):**

| Feature | Priority | Notes |
|---|---|---|
| Website (`r2drop.com`) | P1 | Static HTML, Cloudflare Pages |
| Cross-platform CLI releases | P1 | Linux + Windows binaries via CI |
| Finder badge overlays | P2 | Checkmark badges on uploaded files |
| R2 file browser / download | P2 | Browse bucket contents, download files |
| Client-side encryption | P2 | Encrypt before upload |
| App Sandbox / Mac App Store | P3 | Evaluate feasibility |
| File size warnings | P2 | Configurable threshold warning |

---

## 10. Setup Guides

### 10.1 Generating Sparkle EdDSA Keys

Sparkle 2 uses Ed25519 for signing updates. You generate a key pair once and use it for all future releases.

**Steps:**

1. Download the latest Sparkle release from https://github.com/sparkle-project/Sparkle/releases
2. Extract the archive. The tools are in `bin/`.
3. Run the key generator:
   ```bash
   ./bin/generate_keys
   ```
4. This creates a private key and stores it in your macOS Keychain automatically. It prints the public key to stdout. Copy the public key.
5. Add the public key to `Info.plist`:
   ```xml
   <key>SUPublicEDKey</key>
   <string>NWlOpvs7+ccCaW6557MqyCO94w3KVziS7uAOOxR8gQk=</string>
   ```
6. For CI/CD, export the private key to a file:
   ```bash
   ./bin/generate_keys -x sparkle_private_key
   ```
   Then base64-encode it and add it as a GitHub secret (`SPARKLE_PRIVATE_KEY`). Import on another machine with:
   ```bash
   ./bin/generate_keys -f sparkle_private_key
   ```
7. To sign updates and generate the appcast, run:
   ```bash
   ./bin/generate_appcast /path/to/dmg/folder
   ```
   This generates `appcast.xml` with Ed25519 signatures for each release artifact.

**Important:** Never lose the private key. If you do, you can still rotate keys if your app is also Developer ID signed (Sparkle supports key rotation via code signing trust chain). But it's best to back up the exported key securely (e.g., 1Password, encrypted USB).

### 10.2 Registering with Homebrew Cask

Homebrew Cask is how most developers install macOS GUI apps from the terminal. You submit a PR to the `Homebrew/homebrew-cask` repo.

**Prerequisites:**
- At least one public GitHub Release with a `.dmg` download URL.
- The app must be code-signed and notarized (Gatekeeper-clean).

**Steps:**

1. Fork `https://github.com/Homebrew/homebrew-cask`
2. Generate a cask token (optional helper):
   ```bash
   $(brew --repository homebrew/cask)/developer/bin/generate_cask_token "/Applications/R2Drop.app"
   ```
3. Create the cask file:
   ```bash
   brew create --cask https://github.com/superhumancorp/r2drop/releases/download/v1.0.0/R2Drop.dmg --set-name r2drop
   ```
4. Edit the generated cask (`Casks/r2drop.rb`):
   ```ruby
   cask "r2drop" do
     version "1.0.0"
     sha256 "SHA256_OF_DMG"

     url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/R2Drop.dmg"
     name "R2Drop"
     desc "Upload files to Cloudflare R2 from your Finder"
     homepage "https://r2drop.com"

     app "R2Drop.app"

     zap trash: [
       "~/.r2drop",
       "~/Library/Preferences/com.superhumancorp.r2drop.plist",
     ]
   end
   ```
5. Test locally:
   ```bash
   HOMEBREW_NO_INSTALL_FROM_API=1 brew install --cask ./Casks/r2drop.rb
   brew uninstall --cask r2drop
   brew audit --strict --online --cask ./Casks/r2drop.rb
   ```
6. Commit and open a PR to `Homebrew/homebrew-cask`. One cask per PR. Follow their PR template checklist.
7. For the CLI, create a separate Homebrew formula (not cask) in `Homebrew/homebrew-core` or a custom tap (`superhumancorp/homebrew-tap`).

**Ongoing:** On each new release, update the cask version and sha256 via a PR (or automate with `brew bump-cask-pr r2drop --version NEW_VERSION`).

### 10.3 Generating Apple CI/CD Secrets

The `.env` file and GitHub repo secrets need the following Apple credentials for automated signing and notarization:

| Secret | How to Generate |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Open Keychain Access → export your "Developer ID Application" certificate as a `.p12` file (set a password) → `base64 -i certificate.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` |
| `APPLE_TEAM_ID` | Visible at https://developer.apple.com/account → Membership Details → Team ID |
| `APPLE_ID` | Your Apple ID email address (the one enrolled in the Developer Program) |
| `APPLE_APP_SPECIFIC_PASSWORD` | Generate at https://appleid.apple.com/account/manage → Sign-In and Security → App-Specific Passwords → Generate. Name it "R2Drop CI". |

Add these as repository secrets in GitHub (Settings → Secrets and Variables → Actions) and also populate them in `src/app/.env` for local development.

---

*This is the authoritative PRD for R2Drop P0. All implementation should reference this document.*
