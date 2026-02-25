# TODO - Functional Re-Review (Current State)

Rewritten after your latest code changes (functional/runtime focus only). Items that appear fixed in current code were removed.

## Critical

- [ ] Fix folder uploads on non-Uploads-tab entry points.
  Menu bar drag/drop, Finder extension, and deep-link uploads can still queue directory paths as single jobs, but the Rust engine/hash/upload paths open them as files and fail.
  Refs: `R2Drop/App/MenuBarController.swift:375`, `R2Drop/App/MenuBarController.swift:385`, `R2Drop/FinderExtension/FinderSync.swift:189`, `R2Drop/FinderExtension/FinderSync.swift:200`, `R2Drop/App/DeepLinkHandler.swift:54`, `R2Drop/App/DeepLinkHandler.swift:119`, `R2Drop/App/DeepLinkHandler.swift:232`, `engine/r2-core/src/runner.rs:101`, `engine/r2-core/src/hash.rs:19`, `engine/r2-core/src/upload.rs:127`

## High

- [ ] Make pause/resume actually control in-flight uploads (current UI path is mostly DB state only).
  `pauseJob` only flips SQLite status; the runner uses a local cancel flag that UI cannot signal. `resume` in the FFI API still sets `Uploading`, while the runner only dequeues `Pending`.
  Refs: `R2Drop/App/Queue/QueueViewModel.swift:124`, `R2Drop/App/Queue/QueueViewModel.swift:129`, `R2Drop/App/Queue/QueueViewModel.swift:133`, `R2Drop/App/Queue/QueueViewModel.swift:140`, `engine/r2-core/src/runner.rs:315`, `engine/r2-core/src/runner.rs:354`, `engine/r2-ffi/src/lib.rs:376`, `engine/r2-ffi/src/lib.rs:383`, `engine/r2-ffi/src/lib.rs:384`

- [ ] Move menu bar conflict checks off the UI thread (sync network/FFI call per file).
  Drag/drop queueing still calls `headObjectSync` during conflict resolution, which can block the UI when dropping many files or on slow network.
  Refs: `R2Drop/App/MenuBarController.swift:391`, `R2Drop/App/MenuBarController.swift:417`, `R2Drop/App/MenuBarController.swift:423`, `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:116`

## Medium

- [ ] Normalize exclusion filtering behavior across entry points and fix wildcard matching.
  Finder extension and Uploads-tab folder drop use a prefix-only wildcard matcher (so patterns like `*.tmp` do not work). Menu bar drag/drop and deep-link queueing still bypass exclusions entirely.
  Refs: `R2Drop/FinderExtension/FinderSync.swift:81`, `R2Drop/FinderExtension/FinderSync.swift:220`, `R2Drop/App/Queue/QueueViewModel.swift:194`, `R2Drop/App/Queue/QueueViewModel.swift:205`, `R2Drop/App/Queue/QueueViewModel.swift:233`, `R2Drop/App/MenuBarController.swift:343`, `R2Drop/App/MenuBarController.swift:375`, `R2Drop/App/DeepLinkHandler.swift:54`, `R2Drop/App/DeepLinkHandler.swift:119`, `R2Drop/App/DeepLinkHandler.swift:232`

- [ ] Harden the CLI installer flow for packaged app use.
  The app still shells an install script from the GUI (`Process`), falls back to a repo-relative path, and the script requires `sudo` for default `/usr/local/bin` installs. This is likely to fail or hang in GUI launches without a terminal/password prompt path.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:219`, `R2Drop/App/Settings/SettingsViewModel.swift:230`, `R2Drop/App/Settings/SettingsViewModel.swift:234`, `R2Drop/App/Settings/SettingsViewModel.swift:247`, `scripts/install-cli.sh:21`, `scripts/install-cli.sh:83`, `scripts/install-cli.sh:91`
  Note: I also did not find `install-cli.sh` referenced in `R2Drop/R2Drop.xcodeproj/project.pbxproj` or `R2Drop/project.yml` in this checkout.

## Dead / Unwired / Cleanup

- [ ] `NetworkMonitor` appears unwired (defined but no app callers found in Swift sources).
  Refs: `R2Drop/App/Services/NetworkMonitor.swift:16`

- [ ] `ProgressBridge` is still orphaned.
  Swift defines the callback bridge, and Rust defines the callback type, but no exported FFI API accepts a progress callback in current app wiring.
  Refs: `Packages/R2Bridge/Sources/R2Bridge/UploadProgress.swift:52`, `engine/r2-ffi/src/lib.rs:21`

- [ ] Bridge queue helper APIs in `R2Client` appear unused by the macOS app (`pauseUpload`, `resumeUpload`, `getQueueStatus`, `getHistory`).
  Refs: `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:167`, `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:174`, `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:188`, `Packages/R2Bridge/Sources/R2Bridge/R2Client.swift:197`

- [ ] Finder extension still carries disabled `compress` / `copyURL` plumbing and unused parameters in `queueUploads(...)`.
  This is now clearly marked disabled in UI, but the parameter plumbing is still dead code.
  Refs: `R2Drop/FinderExtension/FinderSync.swift:94`, `R2Drop/FinderExtension/FinderSync.swift:95`, `R2Drop/FinderExtension/FinderSync.swift:180`, `R2Drop/FinderExtension/FinderSync.swift:181`, `R2Drop/FinderExtension/FinderSync.swift:189`, `R2Drop/FinderExtension/FinderSync.swift:192`, `R2Drop/FinderExtension/FinderSync.swift:193`

- [ ] Disabled hotkey implementation still leaves an unused formatting helper.
  Refs: `R2Drop/App/Settings/SettingsViewModel.swift:276`, `R2Drop/App/Settings/SettingsViewModel.swift:280`
