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

### Event Instrumentation (Current Status)

- [x] Instrument core lifecycle events (e.g. `app_launch`, `app_services_started`, settings window opens, incoming URLs).
- [x] Instrument onboarding funnel events (presented, token validation start/success/failure, finish start/success/failure, skip).
- [x] Instrument queue/upload outcomes (enqueue requested, jobs enqueued, completed, batch completed, failed, queue pause/resume/cancel).
- [x] Instrument Finder bridge transfer summaries and token validation summaries.
- [x] Instrument notification permission and notification action clicks.
- [x] Instrument settings changes and CLI install started/success/failure.
- [ ] Complete remaining event coverage gaps and align implementation 1:1 with `INSTRUMENTATION.md` (some documented events are not yet emitted in all branches).
- [ ] Replace/cleanup any stale references to legacy `AnalyticsService` naming in docs/comments (runtime code uses `TelemetryService`).

### Error / Issue Telemetry Quality

- [x] Add rate limiting + aggregation primitives for telemetry anti-spam (`TelemetryRateLimiter`, `TelemetryErrorTracker`).
- [ ] Audit all user-visible and background failure branches to use structured error capture consistently (`TelemetryService.captureError(...)`) instead of ad-hoc event calls/comments.

## Distribution & Packaging

### Homebrew Cask (macOS App)

- [ ] Create `superhumancorp/homebrew-tap`.
- [ ] Add `Casks/r2drop.rb` pointing to GitHub Release DMG URLs.
- [ ] Add `Formula/r2drop-cli.rb` for architecture-specific CLI binaries.
- [ ] Add CI automation to bump cask SHA / version in tap repo.
- [ ] Add CI automation to bump CLI formula SHA / version in tap repo.
- [ ] Validate install flows:
  `brew install --cask superhumancorp/tap/r2drop`
  and `brew install superhumancorp/tap/r2drop-cli`

### App Store (Deferred)

- [ ] Create Apple Distribution certificate + App Store provisioning profile.
- [ ] Audit App Sandbox entitlements for App Store packaging (network/app group/keychain/Finder extension scope).
- [ ] Exclude Sparkle from App Store builds.
- [ ] Add App Store build configuration/scheme.
- [ ] Add CI archive/export/upload workflow for App Store submission.
- [ ] Prepare App Store Connect listing assets and metadata.
- [ ] Submit and address review feedback.

## Dead / Unwired / Cleanup

- [ ] `ProgressBridge` is still orphaned (no exported FFI API currently accepts a progress callback).
- [ ] `R2Client` queue/history helper APIs appear unused in the macOS app (`pauseUpload`, `resumeUpload`, `getQueueStatus`, `getHistory`).
- [ ] Finder extension still carries disabled `compress` / `copyURL` plumbing and unused parameters.

## Notes

- `INSTRUMENTATION.md` is the canonical telemetry specification for event names, funnels, properties, anti-spam rules, and placement guidance.
- `TODO.md` tracks execution status only (what is done vs still open).
