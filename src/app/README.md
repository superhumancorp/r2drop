# R2Drop (macOS App)

R2Drop is a macOS app for uploading files and folders to Cloudflare R2 with fast Finder and menu bar workflows.

## Highlights

- Finder uploads via Quick Action (`Send to R2Drop`) and Finder extension fallback
- Drag and drop uploads to the menu bar icon and Dock icon
- `Upload File(s)...` picker in the menu bar (supports files + folders)
- Background queue with retries, progress, and history
- Multi-account / multi-bucket support
- Copy public URLs after upload (including custom domains)
- macOS app + CLI workflow support

## Documentation

- Product docs: `https://docs.r2drop.com`
- CLI docs: `CLI.md`
- Release docs (local + CI): `RELEASE.md`
- Instrumentation plan: `INSTRUMENTATION.md`

## Local Development

### Prerequisites

- Xcode (current)
- Ruby/Bundler (for Fastlane)
- Rust + `rustup` (for `r2-ffi`)

### Build Rust FFI (required for app builds)

```bash
./scripts/build-rust.sh --release
```

This generates a universal `engine/target/release/libr2_ffi.a` (`arm64` + `x86_64`) used by the app and release builds.

### Build / Run the app

- Xcode schemes:
  - `R2Drop Debug`
  - `R2Drop Production`

For real Finder extension / Quick Action behavior, test the built app from `/Applications` when possible.

## Local Release Automation (Fastlane + Makefile)

Use the new `Makefile` wrappers for local TestFlight/App Store submissions:

```bash
make testflight
make release
make release-minor
make release-major
```

What these do:

- Build the Rust universal FFI archive (`./scripts/build-rust.sh --release`)
- Run Fastlane with the shared `R2Drop Production` scheme
- Auto-generate `BUILD_NUMBER` (UTC timestamp) unless overridden
- Auto-bump `MARKETING_VERSION` for `make release` (patch by default, no file edits)
- Use automatic signing locally by default if provisioning profile UUIDs are not set

See `RELEASE.md` for full env vars, signing requirements, CI/tag releases, and troubleshooting.

## Notes

- Fastlane aliases `testflight` / `appstore` intentionally exist for compatibility with existing scripts/CI commands.
- Manual signing (CI/reproducible local runs) requires App Groups-enabled provisioning profiles for:
  - `com.superhumancorp.r2drop`
  - `com.superhumancorp.r2drop.FinderExtension`
  - `com.superhumancorp.r2drop.QuickActionExtension`
- `GEMINI_API_KEY` can be stored in `.env`, but release-note generation is not wired into the app release workflows in `src/app` by default yet.
