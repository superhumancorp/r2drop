# Release Guide (Local + CI)

This document covers local TestFlight/App Store submissions via Fastlane and the tag-triggered GitHub release pipeline.

## Overview

There are two release paths:

- Local (Fastlane): submit to TestFlight or App Store from your machine
- CI (GitHub Actions): build/sign/notarize/publish desktop releases on `v*` tags

R2Drop release builds require:

- A universal Rust FFI library (`engine/target/release/libr2_ffi.a`) with both `arm64` and `x86_64`
- Valid Apple signing setup
- App Groups-enabled provisioning profiles for the app and both app extensions when using manual signing

## Local Release Commands

Preferred local commands (via `Makefile`):

```bash
make testflight
make release
make release-minor
make release-major
make dmg-release
```

Useful helpers:

```bash
make print-version
make testflight BUILD_NUMBER=123456
make release MARKETING_VERSION=0.2.0 BUILD_NUMBER=123456
```

What `make` does:

- Builds Rust FFI with `./scripts/build-rust.sh --release`
- Validates `fastlane/Fastfile`
- Sources `.env` if present
- Runs Fastlane with auto-generated build numbers and version bumping

For local DMG artifacts:

- `make dmg-release` builds both `arm64` and `x86_64` app bundles, packages DMGs, and notarizes by default
- `make dmg-release-no-notary` skips notarization for faster local iteration
- Artifacts land under `src/app/build/` as:
  - `R2Drop-<version>-aarch64.dmg`
  - `R2Drop-<version>-x86_64.dmg`

## Fastlane Lanes

Canonical lanes:

- `bundle exec fastlane upload_testflight`
- `bundle exec fastlane release_appstore`

Compatibility aliases (still supported):

- `bundle exec fastlane testflight`
- `bundle exec fastlane appstore`

Note: Fastlane may print warnings that lane names conflict with built-in actions (`testflight`, `appstore`). These warnings are noisy but non-fatal.

## Signing Modes (Fastlane)

`fastlane/Fastfile` supports two signing modes:

### 1) Local Automatic Signing (default for local runs)

If no provisioning profile UUID env vars are set and `CI` is not true, Fastlane uses:

- `CODE_SIGN_STYLE=Automatic`
- `export_options.signingStyle = automatic`

This is the easiest local path if Xcode can resolve your signing setup.

Prerequisites for local automatic signing to fully submit to TestFlight/App Store:

- A valid, non-expired Apple Developer session in Xcode (`Xcode > Settings > Accounts`), or
- `APP_STORE_CONNECT_API_KEY_*` env vars so `xcodebuild` can authenticate non-interactively
- A Mac App Store installer certificate in Keychain Access:
  - `3rd Party Mac Developer Installer: ...`
  - or `Mac Installer Distribution: ...`

### 2) Manual Signing (CI / reproducible local runs)

If any provisioning profile UUID env vars are set (or `FORCE_MANUAL_SIGNING=1`), Fastlane switches to manual signing and requires profile UUIDs for all three targets:

- App: `com.superhumancorp.r2drop`
- Finder extension: `com.superhumancorp.r2drop.FinderExtension`
- Quick Action extension: `com.superhumancorp.r2drop.QuickActionExtension`

Required env vars (manual mode):

```bash
PROVISIONING_PROFILE_UUID=<app-profile-uuid>
PROVISIONING_PROFILE_FINDER_EXTENSION_UUID=<finder-extension-profile-uuid>
PROVISIONING_PROFILE_QUICKACTION_EXTENSION_UUID=<quick-action-profile-uuid>
```

Backward-compatible fallback:

- `PROVISIONING_PROFILE_EXTENSION_UUID` is accepted as the Finder extension profile UUID if `PROVISIONING_PROFILE_FINDER_EXTENSION_UUID` is not set.

Important:

- All three provisioning profiles must include the **App Groups** capability.
- The profiles must match the bundle identifiers exactly.

## Required Environment Variables (Fastlane)

Common:

- `APPLE_TEAM_ID` (defaults to `A89MU37ZLB` in `Fastfile`)
- `BUILD_NUMBER` (optional; auto-generated timestamp if omitted)
- `MARKETING_VERSION` (optional; `make release*` auto-computes one if omitted)

App Store Connect upload auth (depending on your local Fastlane setup):

- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_CONTENT` (base64 `.p8`)
- or `APP_STORE_CONNECT_API_KEY_PATH` (path to `.p8`, alternative to `..._CONTENT`)

Local convenience:

- `.env` is sourced by `Makefile` if present
- `GEMINI_API_KEY` can live in `.env`, but release-note generation is **not** wired into app release automation in `src/app` yet

## Rust FFI Requirement (Common Failure)

The app links against `engine/target/release/libr2_ffi.a`.

Production/TestFlight/App Store builds often build both `arm64` and `x86_64`. If your Rust archive is `arm64`-only, you will see linker failures like:

- `Undefined symbol: _r2_*`
- `ld: symbol(s) not found for architecture x86_64`

Fix:

```bash
./scripts/build-rust.sh --release
lipo -info engine/target/release/libr2_ffi.a
```

Expected output includes:

- `x86_64 arm64`

## CI Release Pipeline (GitHub Actions)

### Desktop release (DMG / notarization / GitHub Release)

Workflow:

- `.github/workflows/release.yml`

Trigger:

- Push a tag matching `v*` (example: `v0.1.0`)

What it does:

- Runs Rust quality gates
- Builds universal Rust library
- Builds/signs/notarizes the macOS app
- Builds/signs/notarizes DMG
- Publishes release artifacts

### CI / app build scheme notes

The shared Xcode schemes used by automation are:

- `R2Drop Debug` (CI build checks)
- `R2Drop Production` (Fastlane/TestFlight/App Store/release builds)

If you see scheme-related failures, verify shared schemes exist:

```bash
xcodebuild -workspace R2Drop.xcworkspace -list
```

## Troubleshooting

### `Unknown build action 'Distribution'`

Cause:

- `CODE_SIGN_IDENTITY=Apple Distribution` was passed to `xcodebuild` without shell escaping, so `Distribution` was parsed as a build action.

Status:

- Fixed in `fastlane/Fastfile` by shell-escaping `xcargs` with `Shellwords.join`.

### `requires a provisioning profile with the App Groups feature`

Cause:

- Manual signing mode without valid provisioning profiles for all targets (app + Finder extension + Quick Action extension), or profiles missing App Groups capability.

Fix:

1. Create/install App Store provisioning profiles for:
   - `com.superhumancorp.r2drop`
   - `com.superhumancorp.r2drop.FinderExtension`
   - `com.superhumancorp.r2drop.QuickActionExtension`
2. Ensure each profile includes App Groups entitlement support
3. Export UUID env vars (manual mode), or run local Fastlane without those vars to use automatic signing

### `No Mac App Store installer certificate was found in your keychain`

Cause:

- TestFlight/App Store uploads for macOS require a signed `.pkg`, which must be signed with a Mac installer certificate.

Fix:

1. Install one of these certificates in Keychain Access for team `A89MU37ZLB`:
   - `3rd Party Mac Developer Installer: <Name> (A89MU37ZLB)`
   - `Mac Installer Distribution: <Name> (A89MU37ZLB)`
2. Re-run `make testflight` or `bundle exec fastlane testflight`

### `Your session has expired. Please log in.` during package export

Cause:

- Local automatic signing is trying to fetch signing assets via Xcode, but the Apple Developer account session in Xcode has expired.

Fix (either option):

1. Re-authenticate in `Xcode > Settings > Accounts`, or
2. Set `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, and one of:
   - `APP_STORE_CONNECT_API_KEY_CONTENT` (base64 `.p8`)
   - `APP_STORE_CONNECT_API_KEY_PATH` (path to `.p8`)

### `Couldn't find specified scheme 'R2Drop'`

Cause:

- Automation referenced a non-existent scheme name.

Status:

- Fixed: automation now uses shared schemes `R2Drop Debug` and `R2Drop Production`.

### Fastlane lane-name conflict warnings (`testflight`, `appstore`)

Cause:

- Alias lanes share names with built-in Fastlane actions.

Impact:

- Warning only (non-fatal)

Workaround:

- Use canonical lanes (`upload_testflight`, `release_appstore`) or `make testflight` / `make release`

## Recommended Local Release Workflow

1. Prepare signing in Xcode (automatic signing) or export manual profile UUIDs
2. Confirm Rust universal library builds:

```bash
./scripts/build-rust.sh --release
```

3. Dry-check versions:

```bash
make print-version
```

4. Submit to TestFlight:

```bash
make testflight
```

5. Submit App Store build (auto patch bump):

```bash
make release
```

## Security / Secrets

- Keep `.env` out of git (it is gitignored)
- Prefer GitHub Actions secrets for CI
- Do not commit provisioning profile UUIDs, private keys, or cert passwords
