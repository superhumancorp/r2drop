# TODO - R2Drop Remaining Work

Rewritten with current state as of 2026-02-25. Items fixed in code were removed.

---

## Distribution & Packaging

### Homebrew Cask (macOS app)

- [ ] Create a tap repo `superhumancorp/homebrew-tap` on GitHub.
- [ ] Write `Casks/r2drop.rb` cask formula pointing to the GitHub Release DMG URL.
  Pattern: `url "https://github.com/superhumancorp/r2drop/releases/download/v#{version}/R2Drop-#{version}.dmg"`
  Include `zap trash:` for `~/.r2drop` and `~/Library/Preferences/com.superhumancorp.r2drop.plist`.
- [ ] Write `Formula/r2drop-cli.rb` Homebrew formula for the CLI binary.
  Use `on_arm` / `on_intel` blocks for architecture-specific tarballs from `cli-release.yml`.
- [ ] Add a CI step to `release.yml` that computes the DMG SHA-256 and auto-bumps the cask formula via PR to the tap repo.
- [ ] Add a CI step to `cli-release.yml` that auto-bumps the CLI formula with new SHA-256 values.
- [ ] Test: `brew install --cask superhumancorp/tap/r2drop` and `brew install superhumancorp/tap/r2drop-cli`.

### App Store (deferred — significant lift)

- [ ] Create a separate **Apple Distribution** certificate + Mac App Store provisioning profile in Apple Developer portal.
- [ ] Audit App Sandbox entitlements: the app needs `com.apple.security.network.client`, App Groups, Keychain access, and Finder Sync Extension sandbox scoping.
- [ ] Conditionally exclude Sparkle from the App Store build (Apple handles updates — Sparkle is not allowed).
- [ ] Create a new Xcode scheme or build configuration for App Store distribution.
- [ ] Add CI workflow: `xcodebuild archive` → `.xcarchive` → `xcodebuild -exportArchive` → `.pkg` → `xcrun altool --upload-app`.
- [ ] Set up App Store Connect listing (screenshots, description, keywords, categories).
- [ ] Submit for review. Note: menu-bar-only apps and Finder Sync extensions are allowed but may get extra scrutiny.

---

## Analytics & Telemetry (PostHog)

### SDK Integration

- [ ] Add PostHog Swift SDK via SPM: `https://github.com/PostHog/posthog-ios.git` (from: "3.0.0").
  Add dependency to `project.yml` under R2Drop target's SPM packages.
  Run `xcodegen generate` after updating project.yml.
- [ ] Create `R2Drop/App/Services/AnalyticsService.swift` — thin wrapper around PostHog.
  - Singleton: `AnalyticsService.shared`
  - `configure()` — initializes PostHog with API key `phc_tyaFmZbyRb9RMbinKc16kWLNmQRwZUlUUIcnvQCdCyU` and host `https://us.i.posthog.com`.
  - `track(_ event: String, properties: [String: Any]?)` — sends event only if telemetry is enabled.
  - `identify()` — generates anonymous device ID (hash of hardware UUID), no PII.
  - `setEnabled(_ enabled: Bool)` — reads `config.preferences.allowAnonymousTelemetry`, calls `PostHogSDK.shared.optOut()` / `PostHogSDK.shared.optIn()`.
  - `reset()` — clears PostHog identity on opt-out.
  Refs: new file at `R2Drop/App/Services/AnalyticsService.swift`

### Config Model Changes

- [ ] Add `allowAnonymousTelemetry: Bool` to `R2Preferences` struct.
  Default: `true` (opted in by default, user can opt out in Settings or Onboarding).
  Refs: `Packages/R2Core/Sources/R2Core/Config.swift:58-98`
- [ ] Add TOML parser case: `case "allow_anonymous_telemetry": config.preferences.allowAnonymousTelemetry = str == "true"`.
  Refs: `Packages/R2Core/Sources/R2Core/Config.swift:237-249`
- [ ] Add TOML writer line: `lines.append("allow_anonymous_telemetry = \(p.allowAnonymousTelemetry)")`.
  Refs: `Packages/R2Core/Sources/R2Core/Config.swift:293-308`
- [ ] Add `allow_anonymous_telemetry: bool` to Rust `Preferences` struct (keeps TOML in sync).
  Refs: `engine/r2-core/src/config.rs:53-89`

### Settings UI — Telemetry Toggle

- [ ] Add `@Published var allowAnonymousTelemetry: Bool = true` to SettingsViewModel.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:14-51`
- [ ] Add load: `allowAnonymousTelemetry = prefs.allowAnonymousTelemetry` in `load()`.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:56-79`
- [ ] Add save: `config.preferences.allowAnonymousTelemetry = allowAnonymousTelemetry` in `save()`.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:84-108`
- [ ] Add toggle handler: `toggleAllowAnonymousTelemetry(_ enabled: Bool)` that calls `save()` and `AnalyticsService.shared.setEnabled(enabled)`.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:150-160` (after existing simple toggle saves)
- [ ] Add `GlassToggleRow` in SettingsTabView general section after "Follow symlinks":
  Title: "Allow anonymous telemetry", subtitle: "Help improve R2Drop by sharing anonymous usage data."
  Refs: `R2Drop/App/Settings/SettingsTabView.swift:66-77`

### Onboarding — Telemetry Opt-In

- [ ] Add telemetry toggle to Choose Bucket panel (Panel 5), below the custom domain dropdown, above the "Done" button.
  Use a simple Toggle with the same wording: "Allow anonymous telemetry — Help improve R2Drop".
  Checked by default. User can uncheck before finishing.
  Refs: `R2Drop/App/Onboarding/OnboardingChooseBucketPanel.swift`
- [ ] Wire the toggle to `OnboardingViewModel`: add `@Published var allowAnonymousTelemetry: Bool = true`.
  Persist the choice in `finishSetup()` by loading config, setting `config.preferences.allowAnonymousTelemetry`, and saving.
  Refs: `R2Drop/App/Onboarding/OnboardingViewModel.swift:370-409`

### App Initialization

- [ ] Initialize PostHog in R2DropApp.swift `applicationDidFinishLaunching`:
  Call `AnalyticsService.shared.configure()` after config is loaded.
  Read `config.preferences.allowAnonymousTelemetry` and call `setEnabled()`.
  Refs: `R2Drop/App/R2DropApp.swift` (after config load, before onboarding check)

### Events to Instrument

- [ ] `app_launched` — on every app launch. Properties: `version`, `build_number`, `macos_version`.
- [ ] `upload_started` — when a job enters the queue. Properties: `file_count`, `total_bytes`, `entry_point` (finder_extension | menu_bar_drag | upload_tab | deep_link).
- [ ] `upload_completed` — when a job finishes successfully. Properties: `file_count`, `total_bytes`, `duration_seconds`.
- [ ] `upload_failed` — when a job fails. Properties: `error_code`, `retry_count`.
- [ ] `account_added` — when onboarding or Add Account completes. Properties: `bucket_count`.
- [ ] `settings_changed` — when any setting is toggled. Properties: `setting_name`, `new_value`.
  Refs: Various — `UploadProcessor.swift`, `QueueViewModel.swift`, `OnboardingViewModel.swift`, `SettingsViewModel.swift`, `R2DropApp.swift`

---

## Existing Bugs & Issues

### Critical

- [ ] Fix folder uploads on non-Uploads-tab entry points.
  Menu bar drag/drop, Finder extension, and deep-link uploads can still queue directory paths as single jobs, but the Rust engine opens them as files and fails.
  Refs: `R2Drop/App/MenuBarController.swift:375`, `R2Drop/App/MenuBarController.swift:385`, `R2Drop/FinderExtension/FinderSync.swift:189`, `R2Drop/App/DeepLinkHandler.swift:54`, `engine/r2-core/src/runner.rs:101`

### High

- [ ] Make pause/resume actually control in-flight uploads.
  `pauseJob` only flips SQLite status; the runner uses a local cancel flag that UI cannot signal. `resume` in the FFI API still sets `Uploading`, while the runner only dequeues `Pending`.
  Refs: `R2Drop/App/Queue/QueueViewModel.swift:124-140`, `engine/r2-core/src/runner.rs:315-354`, `engine/r2-ffi/src/lib.rs:376-384`

- [ ] Move menu bar conflict checks off the UI thread.
  Drag/drop queueing still calls `headObjectSync` during conflict resolution, blocking the UI.
  Refs: `R2Drop/App/MenuBarController.swift:391-423`, `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:116`

### Medium

- [ ] Normalize exclusion filtering across all entry points and fix wildcard matching.
  Finder extension and Uploads tab use a prefix-only wildcard matcher (e.g. `*.tmp` doesn't work). Menu bar drag/drop and deep-link bypass exclusions entirely.
  Refs: `R2Drop/FinderExtension/FinderSync.swift:81-220`, `R2Drop/App/Queue/QueueViewModel.swift:194-233`, `R2Drop/App/MenuBarController.swift:343-375`, `R2Drop/App/DeepLinkHandler.swift:54-232`

- [ ] Harden the CLI installer for packaged app use.
  The app shells out to `install-cli.sh`, falls back to repo-relative paths, and the script requires `sudo`. Likely to fail or hang in GUI launches.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:219-247`, `scripts/install-cli.sh`

### Dead / Unwired / Cleanup

- [ ] `ProgressBridge` is still orphaned.
  Swift defines the callback bridge, and Rust defines the callback type, but no exported FFI API accepts a progress callback.
  Refs: `Packages/R2Bridge/Sources/R2Bridge/UploadProgress.swift:52`, `engine/r2-ffi/src/lib.rs:21`

- [ ] Bridge queue helper APIs in `R2Client` appear unused (`pauseUpload`, `resumeUpload`, `getQueueStatus`, `getHistory`).
  Refs: `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:167-197`

- [ ] Finder extension still carries disabled `compress` / `copyURL` plumbing and unused parameters.
  Refs: `R2Drop/FinderExtension/FinderSync.swift:94-95`, `R2Drop/FinderExtension/FinderSync.swift:180-193`

- [ ] Disabled hotkey implementation still leaves an unused formatting helper.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:276-280`
