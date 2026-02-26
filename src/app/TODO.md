# 📋 TODO — R2Drop (Reviewed Checklist)

> Reviewed against current code on 2026-02-25.
> Telemetry event strategy lives in `INSTRUMENTATION.md`. This file tracks execution status only.

---

## ✅ Functional Work (Complete)

- [x] Fix folder uploads for non-Uploads-tab entry points (menu bar, Dock/open-file, Finder extension, deep-link)
- [x] Move menu bar conflict checks off the UI thread (async + background queue worker)
- [x] Normalize exclusion filtering across upload entry points (suffix/prefix/contains wildcards)
- [x] Improve CLI install flow (no hard dependency on bundled script, repo-script fallback, `~/.local` install)
- [x] Fix Finder right-click menu icon rendering (template-style icon + Finder Sync monitoring roots)
- [x] Remove unused hotkey formatting helper

## 🔧 Functional Work (Still Open)

- [ ] Make pause/cancel truly interrupt in-flight single-part uploads — small uploads can finish before pause takes effect (`app-2o3`)
- [ ] Define conflict-check timeout/error UX behavior — currently timeout/error can fall through as "no conflict" (`app-avc`)
- [ ] Bundle prebuilt CLI binary in packaged app builds so "Install CLI" works without source checkout (`app-64r`)

---

## 📊 Analytics & Telemetry (PostHog) — ✅ Complete

### Planning / Spec
- [x] Telemetry strategy, funnels, and event catalog in `INSTRUMENTATION.md`
- [x] Stable anonymous `distinct_id` generation (Keychain-first, session ID separate)

### Core Integration
- [x] PostHog Swift SDK via SPM + project wiring
- [x] Telemetry wrapper/service (`TelemetryService.swift` + sanitizer/rate-limiter/error tracker)
- [x] Initialize on app launch (`TelemetryService.shared.configure()`)

### Config + Preferences
- [x] `allowAnonymousTelemetry` in Swift config + TOML parser
- [x] `allow_anonymous_telemetry` in Rust config (TOML sync)
- [x] Settings UI toggle + persistence
- [x] Onboarding telemetry toggle

### Event Instrumentation
- [x] P0 lifecycle events (`app_launch`, `app_services_started`, settings, incoming URLs)
- [x] P0 onboarding funnel (presented → token validation → finish → skip)
- [x] P0 queue/upload outcomes (enqueue, completed, batch, failed, pause/resume/cancel)
- [x] P0 Finder bridge transfer + token validation summaries
- [x] P0 notification permission + action clicks
- [x] P0 settings changes + CLI install events
- [x] P1 events across all files
- [x] Cleaned up stale `AnalyticsService` references

### Error / Issue Quality
- [x] Rate limiting + aggregation (`TelemetryRateLimiter`, `TelemetryErrorTracker`)
- [x] Structured `captureError()` calls in all failure branches

---

## 📦 Distribution & Packaging

### curl|bash Installer (CLI)
- [x] Created `scripts/install.sh` (detects OS/arch, downloads from GitHub Releases, installs to `~/.local/bin`)
- [x] Hosted at `https://r2drop.com/install.sh`
- [ ] Create first CLI GitHub Release with binaries (install script expects `cli-v*` tags and `r2drop-{os}-{arch}.tar.gz` assets)

### 🍺 Homebrew Tap
- [x] Created `superhumancorp/homebrew-tap` repo with Cask + Formula + CI workflows
- [x] Added `repository_dispatch` trigger in `release.yml` to auto-bump tap
- [ ] Update SHA256 hashes in Cask/Formula once first release is published (`REPLACE_WITH_*_SHA256` placeholders)
- [ ] Validate install flows end-to-end:
  ```bash
  brew tap superhumancorp/tap
  brew install --cask superhumancorp/tap/r2drop
  brew install --formula superhumancorp/tap/r2drop
  ```

### ⚙️ GitHub Actions Workflows
- [x] `.github/workflows/ci.yml` — PR lint + build on push to main
- [x] `.github/workflows/release.yml` — sign, notarize, publish DMGs on tag push, trigger tap bump
- [x] `.github/workflows/cli-release.yml` — cross-compile CLI (macOS arm64/x86_64 + Linux x86_64/aarch64)
- [x] `.github/workflows/deploy-www.yml` — deploy `src/www/` changes to R2

### 🔐 GitHub Secrets (All Configured)
- [x] `APPLE_CERTIFICATE_BASE64` — .p12 signing cert
- [x] `APPLE_CERTIFICATE_PASSWORD`
- [x] `APPLE_TEAM_ID` — `A89MU37ZLB`
- [x] `APPLE_ID` — `com.superhumancorp.r2drop`
- [x] `APPLE_APP_PASSWORD` — app-specific password for notarization
- [x] `SPARKLE_PRIVATE_KEY`
- [x] `CF_API_TOKEN` + `CF_ACCOUNT_ID`
- [x] `TAP_GITHUB_TOKEN` — PAT for homebrew-tap dispatch
- [x] `POSTHOG_API_KEY`
- [x] `PROVISIONING_PROFILE_DEV` / `PROVISIONING_PROFILE_DIST` / `PROVISIONING_PROFILE_MACOS_DEV`

### 🌐 Website (r2drop.com)
- [x] Static site deployed to Cloudflare R2 bucket `r2drop`
- [x] Custom domains: `r2drop.com`, `www.r2drop.com`, `cdn.r2drop.com`
- [x] CF Transform Rules for clean URLs (`/` → `/index.html`, `.html` appending)
- [x] CORS headers via CF Response Header Transform Rule
- [x] Google Analytics (`G-KVJJSZKTX2`)
- [x] PostHog web analytics
- [x] 3D hero logo (Three.js chrome material)
- [ ] Replace template content with actual R2Drop branding/copy

---

## 🍎 App Store (Deferred)

> These steps are needed only when ready for App Store distribution.

- [ ] Create Apple Distribution certificate (different from Developer ID)
- [ ] Create App Store provisioning profile
- [ ] Audit App Sandbox entitlements (network.client, application-groups, keychain ✅)
- [ ] Exclude Sparkle from App Store builds (Apple's built-in updates instead)
- [ ] Add App Store build configuration/scheme in `project.yml`
- [ ] Add CI archive/export/upload workflow (`.github/workflows/appstore.yml`)
- [ ] Prepare App Store Connect listing (screenshots, description, keywords, privacy policy)
- [ ] Submit and address review feedback

---

## 🧹 Dead / Unwired / Cleanup (Complete)

- [x] `ProgressBridge` removed (orphaned, no FFI callback)
- [x] `R2Client` unused methods removed (`pauseUpload`, `resumeUpload`, `getQueueStatus`, `getHistory`)
- [x] Finder extension `compress` / `copyURL` dead plumbing removed

---

## 📝 Notes

- `INSTRUMENTATION.md` — canonical telemetry spec (events, funnels, properties, anti-spam)
- `TODO.md` — execution status only (done vs open)
- `homebrew/` — templates for `superhumancorp/homebrew-tap` (already pushed)
- `scripts/install.sh` — curl|bash installer, live at `r2drop.com/install.sh`
