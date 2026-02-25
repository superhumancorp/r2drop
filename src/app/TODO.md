# TODO - R2Drop (Reviewed Checklist)

Reviewed against current code on 2026-02-25.

This file is now a markdown checklist with completion status validated in code.
Telemetry event strategy/source of truth lives in `INSTRUMENTATION.md`.

## Functional Work (Verified Complete)

- [x] Fix folder uploads for non-Uploads-tab entry points (menu bar, Dock/open-file, Finder extension, deep-link) by queueing individual files instead of directory jobs.
- [x] Move menu bar conflict checks off the UI thread (async conflict checks + background queue worker).
- [x] Normalize exclusion filtering across upload entry points and support suffix/prefix/contains wildcard matching.
- [x] Improve CLI install flow in app code (no hard dependency on bundled script, repo-script fallback, `~/.local` install path, better errors).
- [x] Fix Finder right-click menu icon rendering with template-style icon behavior and improve Finder Sync menu visibility/monitoring roots.
- [x] Remove the previously flagged unused hotkey formatting helper (cleanup item complete).

## Functional Work (Still Open)

- [ ] Make pause/cancel truly interrupt in-flight single-part uploads (small uploads can still finish before pause takes effect). (`app-2o3`)
- [ ] Define and instrument explicit conflict-check timeout/error UX behavior (currently timeout/error can still fall through as "no conflict"). (`app-avc`)
- [ ] Bundle a prebuilt CLI binary in packaged app builds so "Install CLI" works without a source checkout. (`app-64r`)

## Analytics & Telemetry (PostHog)

### Planning / Spec

- [x] Create an implementation-ready telemetry strategy, funnels, and event catalog in `INSTRUMENTATION.md`.
- [x] Document stable anonymous `distinct_id` generation/storage strategy (Keychain-first, session ID separate) in `INSTRUMENTATION.md`.

### Core Integration

- [x] Add PostHog Swift SDK via SPM (`PostHog`) and wire it into the project (`R2Drop/project.yml`).
- [x] Implement telemetry wrapper/service (using `R2Drop/App/Telemetry/TelemetryService.swift` and supporting sanitizer/rate-limiter/error tracker files).
- [x] Initialize telemetry on app launch (`TelemetryService.shared.configure()` in `R2Drop/App/R2DropApp.swift`).

### Config + Preferences

- [x] Add `allowAnonymousTelemetry` to Swift config model and TOML parser/writer (`Packages/R2Core/Sources/R2Core/Config.swift`).
- [x] Add `allow_anonymous_telemetry` to Rust config model (`engine/r2-core/src/config.rs`) to keep TOML in sync.
- [x] Add Settings UI toggle + persistence for anonymous telemetry.
- [x] Add onboarding telemetry toggle and persist the choice in onboarding completion flow.

### Event Instrumentation

- [x] Instrument P0 lifecycle events (`app_launch`, `app_services_started`, settings window, incoming URLs).
- [x] Instrument P0 onboarding funnel (presented, token validation start/success/failure, finish start/success/failure, skip).
- [x] Instrument P0 queue/upload outcomes (enqueue, jobs enqueued, completed, batch completed, failed, pause/resume/cancel).
- [x] Instrument P0 Finder bridge transfer summaries and token validation summaries.
- [x] Instrument P0 notification permission and notification action clicks.
- [x] Instrument P0 settings changes and CLI install started/success/failure.
- [x] Instrument P1 events across all files (lifecycle, onboarding, accounts, menu bar, uploads, queue, notifications, tokens, settings, deep links).
- [x] Clean up stale `AnalyticsService` references in docs/comments.

### Error / Issue Telemetry Quality

- [x] Add rate limiting + aggregation primitives for telemetry anti-spam (`TelemetryRateLimiter`, `TelemetryErrorTracker`).
- [x] Audit all failure branches and add structured `captureError()` calls consistently.

## Distribution & Packaging

### curl|bash Installer (CLI)

- [x] Create `scripts/install.sh` for `curl -fsSL https://r2drop.com/install.sh | bash` installation.
  - Detects OS (macOS/Linux) and arch (arm64/x86_64)
  - Downloads correct binary from GitHub Releases
  - Installs to `~/.local/bin` or `/usr/local/bin`
  - Supports `--bin-dir` and `--version` flags
- [ ] **Host install.sh on r2drop.com** — add a redirect or static file at `https://r2drop.com/install.sh` pointing to `https://raw.githubusercontent.com/superhumancorp/r2drop/main/scripts/install.sh`. Or serve it from the `www/` directory.
- [ ] **Create first GitHub Release with CLI binaries** — the install script expects assets named:
  ```
  r2-cli-aarch64-apple-darwin.tar.gz
  r2-cli-x86_64-apple-darwin.tar.gz
  r2-cli-x86_64-unknown-linux-musl.tar.gz
  r2-cli-aarch64-unknown-linux-musl.tar.gz
  ```
  Each tarball should contain a single file named `r2-cli` (no extension).

### Homebrew Tap

Template files are ready in `/homebrew/` — need to be pushed to a separate repo.

- [ ] **Create the `superhumancorp/homebrew-tap` GitHub repo.** Steps:
  ```bash
  gh repo create superhumancorp/homebrew-tap --public --description "Homebrew tap for R2Drop"
  cd /tmp && git clone https://github.com/superhumancorp/homebrew-tap.git
  # Copy template files from this repo:
  cp -r /path/to/r2drop/homebrew/* /tmp/homebrew-tap/
  cp -r /path/to/r2drop/homebrew/.github /tmp/homebrew-tap/
  cd /tmp/homebrew-tap && git add -A && git commit -m "feat: initial tap with r2drop cask and r2-cli formula"
  git push origin main
  ```
- [ ] **Update SHA256 hashes in Cask/Formula** once first release is published. Replace `REPLACE_WITH_*_SHA256` placeholders:
  ```bash
  # Compute SHA for each release asset:
  curl -fsSL https://github.com/superhumancorp/r2drop/releases/download/v0.1.0/R2Drop-0.1.0-aarch64.dmg | shasum -a 256
  curl -fsSL https://github.com/superhumancorp/r2drop/releases/download/v0.1.0/r2-cli-aarch64-apple-darwin.tar.gz | shasum -a 256
  # etc.
  ```
- [ ] **Add `repository_dispatch` trigger to release workflow.** In `.github/workflows/release.yml`, add after the release is published:
  ```yaml
  - name: Trigger tap bump
    uses: peter-evans/repository-dispatch@v3
    with:
      token: ${{ secrets.TAP_GITHUB_TOKEN }}
      repository: superhumancorp/homebrew-tap
      event-type: new-release
  ```
  This requires a PAT with `repo` scope stored as `TAP_GITHUB_TOKEN` in the main repo's secrets.
- [ ] **Validate install flows** end-to-end:
  ```bash
  brew tap superhumancorp/tap
  brew install --cask superhumancorp/tap/r2drop
  brew install superhumancorp/tap/r2-cli
  ```

### GitHub Release Workflows

- [ ] **Create `.github/workflows/release.yml`** — sign, notarize, publish .dmg. Must produce:
  - `R2Drop-{version}-aarch64.dmg` (Apple Silicon)
  - `R2Drop-{version}-x86_64.dmg` (Intel) — or a universal binary .dmg
  - Trigger Homebrew tap bump after publishing
- [ ] **Create `.github/workflows/cli-release.yml`** — cross-compile CLI. Must produce tarballs:
  - `r2-cli-aarch64-apple-darwin.tar.gz`
  - `r2-cli-x86_64-apple-darwin.tar.gz`
  - `r2-cli-x86_64-unknown-linux-musl.tar.gz`
  - `r2-cli-aarch64-unknown-linux-musl.tar.gz`
- [ ] **Create `.github/workflows/ci.yml`** — PR lint, build, test

### App Store (Deferred)

These steps are needed only when ready for App Store distribution.

- [ ] **Create Apple Distribution certificate** — different from Developer ID Application cert used for direct distribution. Generate via Apple Developer portal > Certificates, Identifiers & Profiles > "Apple Distribution".
- [ ] **Create App Store provisioning profile** — Portal > Profiles > "App Store" type, selecting the R2Drop app ID and the Apple Distribution cert.
- [ ] **Audit App Sandbox entitlements** — App Store requires stricter sandbox. Review `R2Drop.entitlements`:
  - `com.apple.security.network.client` — needed for R2 uploads ✅
  - `com.apple.security.application-groups` — needed for Finder extension IPC ✅
  - `com.apple.security.keychain-access-groups` — needed for token storage ✅
  - Finder Sync Extension must declare its own entitlements separately
  - Remove any entitlements not strictly needed
- [ ] **Exclude Sparkle from App Store builds** — App Store apps use Apple's built-in update mechanism. Add a build flag or separate scheme that strips the Sparkle dependency. Sparkle's `SUPublicEDKey` in Info.plist should also be removed for App Store builds.
- [ ] **Add App Store build configuration/scheme** — create an "R2Drop App Store" scheme in `project.yml` with:
  - `CODE_SIGN_IDENTITY = "Apple Distribution"`
  - `PROVISIONING_PROFILE_SPECIFIER` pointing to the App Store profile
  - No Sparkle framework link
- [ ] **Add CI archive/export/upload workflow** — `.github/workflows/appstore.yml`:
  ```bash
  xcodebuild archive -scheme "R2Drop App Store" -archivePath R2Drop.xcarchive
  xcodebuild -exportArchive -archivePath R2Drop.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath ./export
  xcrun altool --upload-app -f ./export/R2Drop.pkg -t osx -u $APPLE_ID -p $APPLE_APP_SPECIFIC_PASSWORD
  ```
- [ ] **Prepare App Store Connect listing** — screenshots (1280×800, 1440×900, 2560×1600), description, keywords, category (Utilities), privacy policy URL, support URL.
- [ ] **Submit and address review feedback** — Apple may flag the Finder Sync Extension or network entitlements. Have justification ready.

## Dead / Unwired / Cleanup (Completed)

- [x] `ProgressBridge` removed — was orphaned (no FFI API accepts a progress callback). `UploadProgress` struct retained for future use.
- [x] `R2Client` unused methods removed (`pauseUpload`, `resumeUpload`, `getQueueStatus`, `getHistory`). `cancelUpload` kept (actively used).
- [x] Finder extension `compress` / `copyURL` dead plumbing removed — `copyURLKey` constant, disabled UI checkboxes, unused function parameters all cleaned up.

## Notes

- `INSTRUMENTATION.md` is the canonical telemetry specification for event names, funnels, properties, anti-spam rules, and placement guidance.
- `TODO.md` tracks execution status only (what is done vs still open).
- `homebrew/` directory contains ready-to-use templates for `superhumancorp/homebrew-tap`. Copy to the separate repo when created.
- `scripts/install.sh` is the curl|bash installer for the CLI. Host at `r2drop.com/install.sh` when website is live.
