# PRD: R2Drop for macOS — P0 MVP

## Overview

R2Drop is a native macOS menu bar application for uploading files and folders to Cloudflare R2 storage. Users right-click files in Finder, select "Send to R2", and the app handles multipart, parallel, resumable uploads. The monorepo includes a companion cross-platform CLI (`r2-cli`) sharing the same Rust upload engine and config.

The project is open source (MIT), built by Superhuman Intelligence LLC, and models itself after the Tailscale macOS experience: minimal UI, reliable background operation, zero friction.

## Goals

- Deliver a native macOS menu bar app with right-click Finder integration for R2 uploads
- Build a high-performance Rust upload engine with multipart, parallel, resumable uploads
- Provide a guided 5-panel onboarding flow for Cloudflare API token setup and Keychain storage
- Support multi-account management with per-account buckets, paths, and custom domains
- Ship a cross-platform CLI sharing the same Rust engine and `~/.r2drop/` config
- Set up CI/CD for automated building, signing, notarization, and `.dmg` distribution

## Quality Gates

These commands must pass for every user story:
- `cargo clippy --workspace -- -D warnings` — Rust linting
- `cargo test --workspace` — Rust tests
- `xcodebuild build -workspace R2Drop.xcworkspace -scheme R2Drop` — Swift build

## User Stories

---

### Phase 1: Rust Engine

---

### US-001: Rust workspace scaffolding & TOML config
As a developer, I want the Rust workspace structure with config parsing so that all crates have a foundation to build on.

**Acceptance Criteria:**
- [ ] Create `engine/Cargo.toml` workspace with members: `r2-core`, `r2-ffi`, `r2-cli`
- [ ] Create `r2-core/Cargo.toml` with dependencies: `tokio`, `aws-sdk-s3`, `rusqlite`, `toml`, `serde`, `sha2`
- [ ] Create `r2-ffi/Cargo.toml` with `crate-type = ["staticlib"]` and `cbindgen` build dependency
- [ ] Create `r2-cli/Cargo.toml` with `clap` dependency and `r2-core` as local dependency
- [ ] Implement `r2-core/src/config.rs`: parse and write `~/.r2drop/config.toml`
- [ ] Config struct includes: accounts list (name, bucket, path, custom_domain), active_account, preferences (concurrent_uploads, chunk_size_mb, exclusion_patterns, launch_at_login, hide_dock_icon, play_sound)
- [ ] Create `~/.r2drop/` directory if it doesn't exist on first access
- [ ] Support `R2DROP_HOME` env var to override default config directory
- [ ] Config round-trips correctly: read, modify, write preserves all fields

### US-002: S3-compatible R2 client
As the upload engine, I want an S3-compatible client so that I can communicate with Cloudflare R2 buckets.

**Acceptance Criteria:**
- [ ] Implement `r2-core/src/s3.rs` using `aws-sdk-s3` with R2-compatible endpoint configuration
- [ ] `validate_token(token)` calls `GET /user/tokens/verify` on Cloudflare API, returns success/failure
- [ ] `list_accounts(token)` calls `GET /accounts`, returns account ID and name
- [ ] `list_buckets(account_id, token)` calls `GET /accounts/{id}/r2/buckets`, returns bucket names
- [ ] `create_bucket(account_id, bucket_name, token)` calls `PUT /accounts/{id}/r2/buckets/{name}`
- [ ] `head_object(bucket, key)` checks if object exists, returns ETag
- [ ] `put_object(bucket, key, body)` single-part upload for small files
- [ ] `create_multipart_upload(bucket, key)` initiates multipart, returns upload ID
- [ ] `upload_part(bucket, key, upload_id, part_number, body)` uploads a single part
- [ ] `complete_multipart_upload(bucket, key, upload_id, parts)` finalizes multipart
- [ ] `abort_multipart_upload(bucket, key, upload_id)` cancels incomplete multipart
- [ ] All API calls include proper error types with Cloudflare-specific error codes

### US-003: Multipart upload engine
As a user, I want fast parallel uploads so that large files transfer quickly to R2.

**Acceptance Criteria:**
- [ ] Implement `r2-core/src/upload.rs` with async multipart upload logic
- [ ] Stream files from disk using `tokio::fs::File` — never buffer entire file in memory (FR-025)
- [ ] Split files into configurable chunk sizes (default 8 MB, range 5-100 MB) (FR-024)
- [ ] Upload chunks in parallel with configurable concurrency (default 4, range 1-16) (FR-023)
- [ ] Report progress callbacks: bytes uploaded, total bytes, current speed, ETA
- [ ] Handle files of any size (tested with files > 5 GB)
- [ ] Abort multipart upload on cancellation to avoid orphaned parts in R2
- [ ] Small files (< chunk size) use single `put_object` instead of multipart (FR-022)

### US-004: Content hashing & idempotent uploads
As a user, I want duplicate uploads detected so that I don't waste bandwidth re-uploading identical files.

**Acceptance Criteria:**
- [ ] Implement `r2-core/src/hash.rs` with SHA-256 file hashing
- [ ] Hash is computed incrementally while streaming (not a separate pass)
- [ ] Before uploading, call `head_object` to check if key exists
- [ ] Compare local SHA-256 against R2 object ETag to detect duplicates (FR-026)
- [ ] Skip upload if hashes match, report "already exists" status
- [ ] Hashing works correctly for files > 4 GB

### US-005: SQLite queue persistence
As the system, I want a persistent upload queue so that jobs survive app restarts and crashes.

**Acceptance Criteria:**
- [ ] Implement `r2-core/src/queue.rs` using `rusqlite`
- [ ] Queue table schema: id, file_path, r2_key, bucket, account_name, status (pending/uploading/paused/completed/failed), bytes_uploaded, total_bytes, upload_id (multipart), error_message, created_at, updated_at (FR-027)
- [ ] CRUD operations: insert_job, get_job, update_status, update_progress, list_jobs_by_status, delete_job
- [ ] Status transitions: pending → uploading → completed, pending → uploading → failed, uploading → paused → uploading
- [ ] Queue database file: `~/.r2drop/queue.db`
- [ ] Database uses WAL mode for concurrent read/write access (main app + Finder extension)
- [ ] History table in separate `~/.r2drop/history.db`: id, file_name, file_size, r2_key, bucket, account_name, url, uploaded_at

### US-006: Upload resume, retry & offline queueing
As a user, I want uploads to resume after crashes and retry on failures so that I never lose upload progress.

**Acceptance Criteria:**
- [ ] On startup, scan `queue.db` for jobs with status `uploading` — resume from last successful part using stored `upload_id` (FR-028)
- [ ] Retry failed uploads with exponential backoff: 1s, 2s, 4s, 8s, max 60s (FR-029)
- [ ] Maximum 10 retries per job before marking as permanently failed (FR-029)
- [ ] If no network connectivity, keep jobs in `pending` status (FR-030)
- [ ] Automatically resume pending jobs when network is restored (via FFI callback from Swift's `NWPathMonitor`) (FR-030)
- [ ] Handle locked/in-use files: if file can't be read, mark job as failed with descriptive error (FR-031)
- [ ] Paused jobs do not auto-resume — only explicit user action resumes them

### US-007: C FFI bridge (r2-ffi)
As the Swift app, I want a C-compatible interface to the Rust engine so that SwiftUI can drive uploads natively.

**Acceptance Criteria:**
- [ ] Implement `r2-ffi/src/lib.rs` with `extern "C"` wrapper functions
- [ ] FFI functions: `r2_validate_token`, `r2_list_buckets`, `r2_create_bucket`, `r2_queue_upload`, `r2_pause_upload`, `r2_resume_upload`, `r2_cancel_upload`, `r2_get_queue_status`, `r2_get_history`
- [ ] `build.rs` uses `cbindgen` to generate `r2_ffi.h` C header automatically
- [ ] All FFI functions use C-compatible types (pointers, c_char, c_int, etc.)
- [ ] Progress callback: FFI accepts a C function pointer for upload progress updates
- [ ] Error handling: functions return status codes with `r2_get_last_error()` for error messages
- [ ] Memory management: document which side (Rust or Swift) owns each allocation; provide `r2_free_string()` for Rust-allocated strings
- [ ] Generated `r2_ffi.h` is checked into source control for Xcode to reference

---

### Phase 2: Swift Foundation

---

### US-008: Xcode project & Swift package structure
As a developer, I want the Xcode workspace properly configured so that all targets build and link correctly.

**Acceptance Criteria:**
- [ ] Create `R2Drop/R2Drop.xcodeproj` with two targets: main app (`R2Drop`) and Finder extension (`FinderExtension`)
- [ ] Main app target: SwiftUI lifecycle, deployment target macOS 13+, bundle ID `com.superhumancorp.r2drop`
- [ ] Finder extension target: Finder Sync Extension, bundle ID `com.superhumancorp.r2drop.finder-extension`
- [ ] Create `Packages/R2Core/Package.swift` — Swift package with models, config, queue, history managers
- [ ] Create `Packages/R2Bridge/Package.swift` — Swift package wrapping Rust FFI; links `libr2_ffi.a` and imports `r2_ffi.h`
- [ ] Both targets depend on R2Core and R2Bridge packages
- [ ] `R2Drop.entitlements`: Keychain access, App Groups (`group.com.superhumancorp.r2drop`), network client
- [ ] `FinderExtension.entitlements`: App Groups (`group.com.superhumancorp.r2drop`)
- [ ] `Info.plist`: URL scheme `r2drop://`, `SUPublicEDKey` for Sparkle
- [ ] Workspace builds successfully with `xcodebuild` from command line

### US-009: R2Core models & data managers
As the Swift app, I want shared models and data managers so that all views access consistent data.

**Acceptance Criteria:**
- [ ] `Models/Account.swift`: struct with name, bucket, defaultPath, customDomain, accountId properties
- [ ] `Models/UploadJob.swift`: struct with id, filePath, r2Key, bucket, accountName, status enum (pending/uploading/paused/completed/failed), bytesUploaded, totalBytes, uploadId, errorMessage, timestamps
- [ ] `Models/HistoryEntry.swift`: struct with id, fileName, fileSize, r2Key, bucket, accountName, url, uploadedAt
- [ ] `Config.swift`: reads/writes `~/.r2drop/config.toml` from Swift (or delegates to Rust via FFI)
- [ ] `QueueManager.swift`: Swift interface to queue operations (wraps FFI or reads shared SQLite)
- [ ] `HistoryManager.swift`: Swift interface to history operations
- [ ] `AccountManager.swift`: multi-account CRUD, active account switching, persists to config.toml

### US-010: Keychain manager
As the app, I want secure credential storage so that API tokens are never written to disk in plaintext.

**Acceptance Criteria:**
- [ ] Implement `KeychainManager.swift` wrapping `Security.framework` (SecItemAdd, SecItemCopyMatching, SecItemUpdate, SecItemDelete)
- [ ] Keychain service name: `com.superhumancorp.r2drop`
- [ ] Access group: `group.com.superhumancorp.r2drop` (shared with Finder extension)
- [ ] `saveToken(account:token:)` stores token keyed by account name (FR-002)
- [ ] `getToken(account:)` retrieves token silently with no user prompt (FR-003)
- [ ] `deleteToken(account:)` removes token on account logout
- [ ] `updateToken(account:token:)` replaces existing token (FR-008)
- [ ] Token is never logged, printed, or written to config.toml (FR-005)
- [ ] Keychain access works from both main app and Finder extension via shared access group

### US-011: R2Bridge FFI wrapper
As the Swift app, I want a Swift-friendly async API over the C FFI so that SwiftUI views can call Rust functions naturally.

**Acceptance Criteria:**
- [ ] Implement `R2Bridge/Sources/R2Bridge/R2Client.swift`
- [ ] Import `r2_ffi.h` header via a C module map in the package
- [ ] Wrap each FFI function in a Swift async method: `validateToken(_:)`, `listBuckets(accountId:token:)`, `createBucket(accountId:name:token:)`, `queueUpload(filePath:r2Key:bucket:account:)`, `pauseUpload(id:)`, `resumeUpload(id:)`, `cancelUpload(id:)`, `getQueueStatus()`, `getHistory()`
- [ ] Progress callback bridge: convert C function pointer callback to Swift `AsyncStream<UploadProgress>`
- [ ] Proper memory management: free Rust-allocated strings after converting to Swift String
- [ ] Error handling: convert FFI error codes to Swift `R2BridgeError` enum with descriptive messages
- [ ] All methods are thread-safe and callable from any Swift concurrency context

---

### Phase 3: Authentication & Onboarding

---

### US-012: Onboarding carousel flow
As a new user, I want a guided onboarding experience so that I can set up R2Drop quickly on first launch.

**Acceptance Criteria:**
- [ ] 5-panel carousel in a centered, non-resizable window (~520x400pt) (FR-015)
- [ ] Panel 1 (Welcome): app icon with bounce animation, headline "R2Drop", subheadline "Upload files to Cloudflare R2 right from your Finder", three feature pills ("Right-click to upload", "Blazing fast", "Open source")
- [ ] Panel 2 (How It Works): 3 vertically stacked steps with icons explaining right-click → upload → clipboard flow
- [ ] Panel 3 (Create Token): "Open Cloudflare Dashboard" button opens browser to API tokens page; collapsible step-by-step guide with annotated screenshots; "I already have a token" link skips to Panel 4
- [ ] Panel 4 (Paste Token): large text field; validates on paste via Cloudflare API; spinner during validation; green checkmark on success; red error on failure; stores valid token in Keychain
- [ ] Panel 5 (Choose Bucket): dropdown of buckets (fetched after Panel 4); "Create New Bucket" inline form; default upload path field; optional custom domain field; "Done" button with celebratory animation
- [ ] Dot indicators showing current panel position
- [ ] Smooth left-to-right slide transitions (< 300ms, respects `accessibilityDisplayShouldReduceMotion`)
- [ ] "Back" button on panels 2-5; "Skip setup" link on panels 1-3
- [ ] Keyboard navigation: Tab between fields, Enter for Continue/Done, Escape closes with confirmation
- [ ] If user skips, app launches into menu bar with no account; Accounts tab shows "Set up your first account" card
- [ ] Re-onboarding (all accounts removed) starts from Panel 3

### US-013: Token validation & storage
As a user, I want my token validated immediately on paste so that I know it works before proceeding.

**Acceptance Criteria:**
- [ ] On paste, call `GET /user/tokens/verify` with `Authorization: Bearer <token>` (FR-001)
- [ ] On valid token, call `GET /accounts` to get account ID and name
- [ ] Call `GET /accounts/{id}/r2/buckets` to populate bucket list for Panel 5
- [ ] Store valid token in macOS Keychain via KeychainManager (FR-002)
- [ ] Wipe plaintext token from memory after Keychain storage
- [ ] On invalid token, show inline error: "This token doesn't appear to be valid. Please check that you copied the full token." with "Clear & Try Again" button
- [ ] On app launch, retrieve token silently from Keychain (FR-003)
- [ ] Periodic token verification: on launch and every 24 hours (FR-004)
- [ ] If token revoked, show notification: "Your R2Drop token has expired. Click here to set up a new one."
- [ ] Token never written to config.toml, logs, or crash reports (FR-005)

### US-014: Multi-account management
As a power user, I want to manage multiple Cloudflare accounts so that I can upload to different R2 buckets.

**Acceptance Criteria:**
- [ ] Support multiple accounts, each with: display name, API token (Keychain), bucket, default path, custom domain (FR-006)
- [ ] "Add Account" triggers token setup flow (panels 3-5) without welcome screens (FR-007)
- [ ] "Update Token" on existing account re-opens paste+validate flow, replaces Keychain entry (FR-008)
- [ ] "Log Out" removes Keychain entry and account config with confirmation dialog (FR-009)
- [ ] Active account selector in menu bar dropdown
- [ ] Uploads scoped to active account's credentials, bucket, and path (FR-032)
- [ ] Account switching persists to config.toml

---

### Phase 4: Core UI

---

### US-015: Menu bar controller & drag-and-drop
As a user, I want a persistent menu bar icon so that I can monitor and control R2Drop at a glance.

**Acceptance Criteria:**
- [ ] Persistent `NSStatusItem` in macOS menu bar with R2Drop icon (FR-034)
- [ ] Icon animates (rotating arrows or pulsing) during active uploads (FR-035)
- [ ] Dropdown menu: On/Off toggle, active account name + account switcher submenu, "X of Y uploaded" queue summary, "Preferences...", "Quit R2Drop" (FR-036)
- [ ] Drag-and-drop: accept file drops on menu bar icon to trigger upload (FR-066)
- [ ] Dropped files respect confirmation dialog (unless "Never ask again") and active account
- [ ] Menu bar icon uses SF Symbols or custom asset from Assets.xcassets
- [ ] Works correctly in both light and dark menu bar appearances

### US-016: Finder Sync Extension & confirmation dialog
As a user, I want to right-click files in Finder and send them to R2 so that uploading is effortless.

**Acceptance Criteria:**
- [ ] Implement `FinderSync.swift` as Finder Sync Extension target (FR-017)
- [ ] Register "Send to R2" in Finder context menu for all files and folders
- [ ] Support bulk selection — multiple files/folders queued at once (FR-018)
- [ ] Confirmation dialog: file/folder name and size, "Compress as ZIP" toggle (default off), "Copy URL to clipboard" toggle (default on), "Never ask again" checkbox (default unchecked), Upload/Cancel buttons (FR-019)
- [ ] "Never ask again" skips dialog on future uploads using saved preferences (FR-020)
- [ ] Extension writes `UploadJob` records to shared `queue.db` via App Groups (FR-021)
- [ ] Main app's queue manager polls shared SQLite and processes new jobs
- [ ] Skip files matching exclusion patterns from Settings (`.DS_Store`, `._*`, etc.) (FR-049)

---

### Phase 5: Preferences Window

---

### US-017: Preferences window — Queue tab
As a user, I want to see and control active uploads so that I can monitor progress and manage the queue.

**Acceptance Criteria:**
- [ ] Scrollable list of active upload jobs: file name, file size, progress bar, upload speed, status (FR-037)
- [ ] Aggregate status bar: average upload rate, "Files X of Y" progress (FR-038)
- [ ] Pause / Resume / Cancel buttons per job; Cancel shows confirmation alert (FR-039)
- [ ] "Browse" button opens `https://dash.cloudflare.com/<account_id>/r2/default/buckets/<bucket_name>` in browser (FR-040)
- [ ] Queue tab is the default tab when uploads are active
- [ ] Real-time progress updates from Rust engine via FFI progress callbacks

### US-018: Preferences window — Accounts tab
As a user, I want to manage my R2 accounts in preferences so that I can add, edit, and remove accounts.

**Acceptance Criteria:**
- [ ] Sidebar list of configured accounts; clicking shows details on the right (FR-041)
- [ ] "Add Account" button opens guided token setup flow (panels 3-5) (FR-042)
- [ ] Account detail panel: editable name, bucket dropdown (fetched from API), default path field (validated), custom domain URL field (FR-043)
- [ ] "Update Token" opens token paste+validate flow; "Log Out" removes account with confirmation (FR-044)
- [ ] Accounts tab is the default tab when no uploads are active
- [ ] If no accounts configured, show "Set up your first account" card

### US-019: Preferences window — Settings tab
As a user, I want to configure R2Drop's behavior so that it works the way I prefer.

**Acceptance Criteria:**
- [ ] Toggle: Hide Dock icon / menu-bar-only mode (FR-045)
- [ ] Toggle: Launch R2Drop at Login (FR-045)
- [ ] Toggle: Play system sound on upload complete, default on (FR-045)
- [ ] "Install CLI" button: copies r2drop binary to `/usr/local/bin`; shows installed version if present (FR-046)
- [ ] Global Upload Hotkey: key recorder field with Record/Clear buttons (FR-047)
- [ ] Concurrent uploads slider/stepper: 1-16, default 4 (FR-048)
- [ ] Chunk size slider/stepper: 5-100 MB, default 8 MB (FR-048)
- [ ] File exclusion list table with add/edit/remove; defaults: `.DS_Store`, `._*`, `.Thumbs.db`, `.Spotlight-V100`, `.Trashes`, `__MACOSX`, `.fseventsd` (FR-049)
- [ ] Config directory path field showing `~/.r2drop` with option to change; overridable via `R2DROP_HOME` (FR-050)
- [ ] Symlink toggle: "Follow symlinks" vs "Skip symlinks", default skip (FR-051)

### US-020: Preferences window — History tab
As a user, I want to browse my upload history so that I can find and copy URLs of previously uploaded files.

**Acceptance Criteria:**
- [ ] Searchable, scrollable list of completed uploads: file name, file size, upload timestamp, R2 URL (FR-052)
- [ ] "Copy URL" button per entry; uses custom domain if configured, otherwise R2 public URL (FR-053)
- [ ] History persisted in `history.db`; no automatic pruning; manual "Clear History" button (FR-054)
- [ ] Search filters by file name
- [ ] Entries sorted by most recent first

### US-021: Preferences window — About tab & auto-update
As a user, I want version info and automatic updates so that R2Drop stays current.

**Acceptance Criteria:**
- [ ] App icon, "R2Drop for macOS" title, version number from build info (FR-055)
- [ ] Links: Privacy Policy (r2drop.com/privacy), Terms of Service (r2drop.com/terms), Report an Issue (GitHub Issues URL) (FR-056)
- [ ] Copyright: "2026 Superhuman Intelligence LLC. All rights reserved." and trademark notice (FR-057)
- [ ] "Automatically check for updates" checkbox, default on (FR-058)
- [ ] "Check Now" button triggers Sparkle update check (FR-058)
- [ ] "Last checked: [timestamp]" label (FR-058)
- [ ] Sparkle framework integrated with Ed25519 key `NWlOpvs7+ccCaW6557MqyCO94w3KVziS7uAOOxR8gQk=`

---

### Phase 6: Supporting Features

---

### US-022: Deep link handling
As a user or CLI, I want URL scheme support so that other tools can trigger R2Drop actions.

**Acceptance Criteria:**
- [ ] Register `r2drop://` URL scheme in Info.plist
- [ ] Handle in `AppDelegate.application(_:open:)`
- [ ] `r2drop://upload?path=<path>` queues file for upload, respects confirmation dialog (FR-060)
- [ ] `r2drop://upload?path=<path>&compress=true` queues with ZIP compression
- [ ] `r2drop://preferences` and tab-specific variants (`/queue`, `/accounts`, `/settings`, `/history`, `/about`) open corresponding tabs
- [ ] `r2drop://account?name=<name>` switches active account
- [ ] `r2drop://browse` and `r2drop://browse?account=<name>` open bucket in browser
- [ ] `r2drop://auth/setup` opens token setup wizard
- [ ] `r2drop://status` returns health check info
- [ ] Deep links cannot exfiltrate credentials or modify account settings without user action (FR-059)
- [ ] Upload deep links validate that path exists and is readable (FR-060)

### US-023: Notifications & system sounds
As a user, I want native notifications so that I know when uploads complete or fail.

**Acceptance Criteria:**
- [ ] Use `UNUserNotificationCenter` for macOS notifications (FR-061)
- [ ] Notify on: upload complete (single/batch), upload failed (with error summary), upload paused (network lost), token expired (with "Set up new token" action) (FR-062)
- [ ] Play macOS system sound on upload complete if enabled in Settings (FR-063)
- [ ] Notification actions: "Copy URL" on success, "Retry" on failure, "Set up token" on expiry
- [ ] Request notification permission on first launch

### US-024: Conflict resolution
As a user, I want to choose what happens when uploading to an existing path so that I don't accidentally overwrite files.

**Acceptance Criteria:**
- [ ] When upload target already exists in R2, show dialog: Overwrite / Skip / Rename (FR-065)
- [ ] Rename appends `-<timestamp>` suffix to filename
- [ ] "Apply to all" checkbox applies choice to remaining conflicts in the batch
- [ ] Choice is per-session (resets on app restart)
- [ ] Dialog shows existing file's size and last modified date for comparison

### US-025: Dark mode & accessibility
As a user, I want R2Drop to look correct in both light and dark mode and respect accessibility settings.

**Acceptance Criteria:**
- [ ] All UI respects `NSAppearance` / SwiftUI `colorScheme` (FR-064)
- [ ] No hardcoded colors — use system semantic colors throughout
- [ ] All animations respect `accessibilityDisplayShouldReduceMotion`
- [ ] Tested in both light and dark mode with no visual issues
- [ ] Sufficient contrast ratios for all text and interactive elements

### US-026: Audit logging
As an operator, I want structured logs so that I can debug upload issues and audit activity.

**Acceptance Criteria:**
- [ ] Log all upload activity: start, progress milestones, complete, fail, retry (FR-067)
- [ ] Log to `~/.r2drop/logs/r2drop.log` with rolling file rotation (FR-067)
- [ ] Configurable max log file size and retention count
- [ ] Log includes: timestamp, account, bucket, file path, file size, R2 key, status, error details (FR-068)
- [ ] Never log API tokens or credentials (FR-068)
- [ ] Logging works in both app and CLI contexts

---

### Phase 7: CLI

---

### US-027: CLI authentication & login
As a CLI user, I want to authenticate with Cloudflare so that I can upload files from the terminal.

**Acceptance Criteria:**
- [ ] `r2drop login` opens `https://dash.cloudflare.com/profile/api-tokens` in default browser and prints inline setup instructions (FR-010)
- [ ] CLI prompts `Paste your API token:` with masked/hidden input (FR-011)
- [ ] Validates token and stores in OS keychain; confirms success (FR-011)
- [ ] `r2drop login --token <token>` accepts token as argument for scripting (FR-012)
- [ ] If R2Drop app is running, can trigger deep link `r2drop://auth/setup` (FR-013)
- [ ] CLI entry point uses `clap` for argument parsing

### US-028: CLI upload, status & queue commands
As a CLI user, I want to upload files and check status so that I can use R2Drop in scripts and terminals.

**Acceptance Criteria:**
- [ ] `r2drop upload <path>` queues file or folder for upload
- [ ] `r2drop upload <path> --compress` compresses as ZIP before uploading
- [ ] `r2drop upload <path> --account <name>` uploads using a specific account
- [ ] `r2drop status` shows daemon health, R2 connectivity, active account, queue summary
- [ ] `r2drop queue` shows active upload queue with progress bars
- [ ] If app daemon is running, CLI communicates via Unix socket at `~/.r2drop/r2drop.sock`
- [ ] If app is not running, CLI operates standalone using r2-core directly
- [ ] Progress display: file name, percentage, speed, ETA

### US-029: CLI accounts, config, history & output
As a CLI user, I want to manage accounts and view history so that I have full control from the terminal.

**Acceptance Criteria:**
- [ ] `r2drop accounts` lists configured accounts
- [ ] `r2drop accounts --add` triggers login flow
- [ ] `r2drop accounts --remove <name>` removes account with confirmation
- [ ] `r2drop accounts --switch <name>` switches active account
- [ ] `r2drop config get <key>` / `r2drop config set <key> <value>` reads/writes config values
- [ ] `r2drop history` lists upload history (most recent first)
- [ ] `r2drop history --limit <n>` limits output count
- [ ] `r2drop history --search <query>` filters by filename
- [ ] All commands support `--json` flag for structured JSON output
- [ ] Default output: human-readable colored terminal output

---

### Phase 8: CI/CD & Distribution

---

### US-030: Build scripts
As a developer, I want build scripts so that I can compile and package R2Drop from the command line.

**Acceptance Criteria:**
- [ ] `scripts/build-rust.sh` compiles Rust workspace, produces `libr2_ffi.a` and `r2_ffi.h`; supports ARM and x86_64; copies outputs to where R2Bridge package expects them
- [ ] `scripts/install-cli.sh` builds `r2-cli` in release mode, copies `r2drop` binary to `/usr/local/bin`
- [ ] `scripts/generate-dmg.sh` packages signed `.app` into `.dmg` with drag-to-Applications layout
- [ ] All scripts are executable, have usage instructions, and handle errors gracefully
- [ ] `build-rust.sh` supports `--release` flag for optimized builds

### US-031: CI workflow — PR checks
As a contributor, I want automated CI so that pull requests are validated before merge.

**Acceptance Criteria:**
- [ ] `.github/workflows/ci.yml` triggers on pull requests to `main`
- [ ] Lint Swift with SwiftLint
- [ ] Lint Rust with `cargo clippy --workspace -- -D warnings`
- [ ] Build Xcode workspace with `xcodebuild build`
- [ ] Build Rust workspace with `cargo build --workspace`
- [ ] Run Rust tests with `cargo test --workspace`
- [ ] Run Swift tests with `xcodebuild test` (if test targets exist)
- [ ] CI uses macOS runner with Xcode and Rust toolchain pre-installed

### US-032: Release & distribution workflows
As a maintainer, I want automated releases so that users get signed, notarized builds and CLI binaries.

**Acceptance Criteria:**
- [ ] `.github/workflows/release.yml` triggers on `v*` tags
- [ ] Builds macOS app in Release mode
- [ ] Signs with Developer ID certificate from `APPLE_CERTIFICATE_BASE64` secret
- [ ] Notarizes with Apple using `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`
- [ ] Packages as `.dmg` via `scripts/generate-dmg.sh`
- [ ] Generates Sparkle appcast update entry
- [ ] Publishes `.dmg` + appcast to GitHub Releases
- [ ] `.github/workflows/cli-release.yml` triggers on `cli-v*` tags
- [ ] Cross-compiles `r2-cli` for macOS (ARM + x86), Linux (x86_64 + ARM64), Windows (x86_64)
- [ ] Publishes platform binaries to GitHub Releases

## Functional Requirements

- FR-001: Validate API token via `GET /user/tokens/verify` on paste
- FR-002: Store API token in macOS Keychain (service: `com.superhumancorp.r2drop`)
- FR-003: Retrieve token from Keychain silently on app launch
- FR-004: Periodically verify token validity (on launch + every 24h)
- FR-005: Never write API token to disk (config, logs, crash reports)
- FR-006: Support multiple Cloudflare accounts with isolated credentials
- FR-007: "Add Account" triggers guided setup without welcome screen
- FR-008: "Update Token" replaces existing Keychain entry
- FR-009: "Log Out" removes Keychain entry and config with confirmation
- FR-010: CLI `login` opens Cloudflare dashboard and prints setup instructions
- FR-011: CLI prompts for token with masked input, validates, stores in keychain
- FR-012: CLI `login --token <token>` accepts token argument for scripting
- FR-013: CLI triggers app auth via `r2drop://auth/setup` deep link
- FR-014: Distribute as `.dmg` with drag-to-Applications install
- FR-015: Present onboarding wizard on first launch
- FR-016: Run as menu bar app with optional Dock icon
- FR-017: Finder Sync Extension with "Send to R2" context menu
- FR-018: Support bulk file/folder selection in Finder
- FR-019: Confirmation dialog with file info, compress toggle, copy URL toggle
- FR-020: "Never ask again" skips dialog with saved preferences
- FR-021: Finder extension writes to shared `queue.db` via App Groups
- FR-022: S3-compatible API with multipart upload
- FR-023: Parallel uploads (default 4, configurable 1-16)
- FR-024: Configurable chunk size (default 8 MB, range 5-100 MB)
- FR-025: Stream from disk, never buffer entire files
- FR-026: Idempotent uploads via SHA-256/ETag comparison
- FR-027: Persistent queue with status tracking in SQLite
- FR-028: Resume multipart uploads after crash/restart
- FR-029: Exponential backoff retry (max 10 retries, max 60s delay)
- FR-030: Offline queueing with automatic resume on connectivity
- FR-031: Handle locked files with descriptive error
- FR-032: Uploads scoped to active account
- FR-033: Copy URL (custom domain or R2 public) to clipboard on completion
- FR-034: Persistent menu bar icon
- FR-035: Animated icon during uploads
- FR-036: Menu bar dropdown with toggle, account switcher, queue summary
- FR-037: Queue tab with per-job progress
- FR-038: Aggregate upload status bar
- FR-039: Pause/Resume/Cancel per upload job
- FR-040: "Browse" button opens R2 dashboard
- FR-041: Accounts sidebar with click-to-detail
- FR-042: "Add Account" opens guided setup flow
- FR-043: Account detail: editable name, bucket, path, custom domain
- FR-044: "Update Token" and "Log Out" buttons
- FR-045: Settings toggles: hide dock, launch at login, sound on complete
- FR-046: CLI install button
- FR-047: Global upload hotkey recorder
- FR-048: Upload performance controls (concurrency, chunk size)
- FR-049: Configurable file exclusion patterns
- FR-050: Config directory path (overridable via `R2DROP_HOME`)
- FR-051: Symlink handling toggle
- FR-052: Searchable upload history
- FR-053: "Copy URL" per history entry
- FR-054: Persistent history with manual clear
- FR-055: About tab with version info
- FR-056: Links to privacy, terms, and issue tracker
- FR-057: Copyright and trademark notice
- FR-058: Sparkle auto-update with check now button
- FR-059: Deep links cannot exfiltrate credentials
- FR-060: Upload deep links respect confirmation dialog and validate paths
- FR-061: `UNUserNotificationCenter` for notifications
- FR-062: Notify on complete, fail, pause, token expiry
- FR-063: System sound on upload complete (configurable)
- FR-064: Full dark mode support, no hardcoded colors
- FR-065: Conflict resolution dialog (overwrite/skip/rename)
- FR-066: Drag-and-drop onto menu bar icon
- FR-067: Structured audit logging to rolling log files
- FR-068: Logs include upload metadata, never credentials

## Non-Goals (Out of Scope for P0)

- File download, sync, or bucket content browsing
- Cloudflare OAuth (not supported for third-party desktop apps)
- Client-side encryption before upload
- Finder badge overlays on uploaded files
- Website / landing page (r2drop.com deferred)
- Mac App Store / App Sandbox distribution
- File size warning thresholds
- Team or shared account features
- Telemetry or analytics
- Cross-platform GUI (CLI only for Linux/Windows)
- Directory watch / auto-sync mode

## Technical Considerations

- **Rust staticlib**: single binary, no runtime dependencies. Linked directly into the macOS app bundle via R2Bridge package.
- **App Groups IPC**: Finder extension writes to shared `queue.db` in the App Groups container (`group.com.superhumancorp.r2drop`), not XPC.
- **Keychain shared access**: both app and Finder extension access same Keychain items via shared access group.
- **cbindgen**: auto-generates C header from Rust FFI. Header checked into source for Xcode to reference without Rust toolchain.
- **SQLite WAL mode**: concurrent reads from Finder extension while main app writes.
- **Unix socket IPC**: CLI communicates with running app via `~/.r2drop/r2drop.sock`. Falls back to standalone r2-core if app not running.
- **Sparkle Ed25519**: public key `NWlOpvs7+ccCaW6557MqyCO94w3KVziS7uAOOxR8gQk=` in Info.plist.
- **Developer ID Application** cert required (not Apple Distribution) for outside-App-Store distribution.
- **Minimum deployment**: macOS 13 Ventura.

## Success Metrics

- All 68 functional requirements implemented and verified
- Rust engine passes `cargo clippy` and `cargo test` with zero warnings
- Xcode workspace builds with `xcodebuild build` successfully
- Onboarding completes end-to-end: token paste → validation → bucket selection → first upload
- Upload speed matches or exceeds direct `aws s3 cp` for equivalent file sizes
- Menu bar app launches in < 2 seconds
- Uploads resume correctly after app crash/restart
- CLI and app share config and credentials seamlessly
- CI/CD produces signed, notarized `.dmg` on tagged release
- All UI renders correctly in both light and dark mode

## Open Questions

- Should Sparkle check for updates on a fixed interval or only on app launch?
- What is the maximum file size to target for testing? (5 GB, 50 GB, 100 GB?)
- Should the CLI support `--watch` mode for continuous directory monitoring? (likely P1)
- Should a "Recent Uploads" section appear in the menu bar dropdown? (likely P1)
- Should the Finder extension show badge overlays on uploaded files? (deferred per scope)