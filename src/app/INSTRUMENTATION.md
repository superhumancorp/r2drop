# R2Drop PostHog Instrumentation Plan

## Purpose

This document defines an implementation-ready telemetry strategy for R2Drop (macOS app + Finder extension integration) using PostHog.

Goals:

- Measure activation and first-value conversion
- Understand upload entrypoint usage (Finder, menu bar, Dock, deep links)
- Track reliability and user-facing failures without analytics spam
- Provide a clear event catalog and exact code placement guidance for an AI agent to implement with minimal guesswork

Non-goals:

- Crash reporting replacement (PostHog is not a full crash reporter)
- Full upload progress telemetry (too noisy)
- Raw file path / token / bucket/account PII collection

## Guiding Principles

1. Instrument user intent and state transitions, not polling loops.
2. Prefer terminal events over high-frequency progress events.
3. Send structured, sanitized properties only.
4. Capture first occurrence of an error immediately, then aggregate repeats.
5. Track from the main app whenever possible (Finder extension should avoid direct analytics network calls).

## Recommended Architecture (Implementation Shape)

Create a thin analytics layer in Swift and keep PostHog SDK usage behind it.

Suggested files:

- `R2Drop/App/Telemetry/TelemetryService.swift`
- `R2Drop/App/Telemetry/TelemetryEvent.swift`
- `R2Drop/App/Telemetry/TelemetrySanitizer.swift`
- `R2Drop/App/Telemetry/TelemetryRateLimiter.swift`
- `R2Drop/App/Telemetry/TelemetryErrorTracker.swift`

Core API (suggested):

```swift
@MainActor
protocol AnalyticsTracking {
    func track(_ event: String, _ properties: [String: Any])
    func screen(_ name: String, _ properties: [String: Any])
    func identify(distinctId: String, properties: [String: Any]?)
    func alias(_ newId: String, for oldId: String)
    func reset()
    func flush()
    func captureError(_ error: Error, context: ErrorContext)
}
```

Important implementation details:

- `TelemetryService` should own session state (`session_id`, app start timestamp, first-launch flags cached in memory).
- `TelemetrySanitizer` should hash or bucket sensitive values before capture.
- `TelemetryRateLimiter` should dedupe repeated events by key + time window.
- `TelemetryErrorTracker` should aggregate repeated errors and flush summary events periodically / on terminate.

## Privacy and Data Hygiene (Required)

Do **not** send:

- API tokens
- `tokenId`
- raw `accountId`
- raw file paths
- raw `r2Key`
- raw account names
- raw bucket names
- raw custom domains
- full error strings if they may contain file paths or URLs

Send sanitized alternatives:

- `account_name_hash`
- `bucket_hash`
- `custom_domain_hash`
- `r2_key_ext` (extension only) and `r2_key_depth` (int)
- `file_ext`, `file_count`, `contains_directory`
- `total_bytes` and `size_bucket`
- `error_type`, `error_domain`, `error_code`, `error_message_hash`

Hashing recommendation:

- Use `SHA256(install_salt + ":" + value)` where `install_salt` is a random UUID generated once and stored locally (config or keychain).
- This allows consistent grouping per install without exposing raw values.

## Identity Model

Use 2 IDs:

1. `distinct_id` (stable anonymous install ID)
2. `session_id` (new UUID each app launch)

Do not identify users by email or Cloudflare account ID unless explicit product/legal approval exists.

Recommended people properties (low-risk):

- `app_version`
- `build_number`
- `os_version`
- `has_accounts` (bool)
- `account_count`
- `hide_dock_icon`
- `launch_at_login`
- `analytics_opt_in` (if/when added)

## Common Event Properties (Attach to Nearly All Events)

These should be added centrally by `TelemetryService`:

- `session_id`
- `app_version`
- `build_number`
- `platform = "macOS"`
- `os_version`
- `is_debug_build`
- `app_process = "main_app"` or `"finder_extension"` (if extension events are later proxied)
- `timestamp_ms` (optional if SDK adds this)

Context-specific common properties:

- `entrypoint` (`finder_context_menu`, `finder_bridge`, `menu_bar_drag`, `menu_bar_picker`, `dock_open`, `deep_link`, `queue_tab_drag`)
- `surface` (`onboarding`, `menu_bar`, `settings`, `queue`, `notification`, `finder`, `app_delegate`)

## Anti-Spam Strategy (Required)

### 1) Never instrument timer ticks directly

Do **not** emit events on every call to:

- `R2Drop/App/Services/UploadMonitor.swift:79` (`poll`)
- `R2Drop/App/Queue/QueueViewModel.swift:54` (`poll`)
- `R2Drop/App/MenuBarController.swift:149` (`checkUploadState`)
- `R2Drop/App/Services/FinderQueueBridge.swift:48` (`transferPendingJobs`) when no jobs

Only emit on transitions / meaningful outcomes.

### 2) Error dedupe and aggregation

For non-fatal errors:

- Emit first occurrence immediately (`app_error`)
- Suppress identical repeats for 5 minutes using dedupe key:
  - `component + operation + error_domain + error_code + error_message_hash`
- Increment local counter
- Flush periodic summary as `app_error_summary` every 60s or on app termination

### 3) Upload events: terminal only by default

Track:

- queued
- started (optional; one-time)
- completed
- failed
- paused
- resumed
- canceled

Do not track progress percentages by default.

### 4) Background validation and polling summaries

For periodic systems (token validation, finder bridge), prefer one summary event per run:

- counts, duration, outcomes
- plus a deduped per-account invalid event when status changes to invalid

## Funnel Strategy

## Funnel A: Activation (Install -> Working Account)

Primary question: Can a new user set up an account successfully?

Steps:

1. `app_launch`
2. `onboarding_presented`
3. `onboarding_token_validation_started`
4. `onboarding_token_validation_succeeded`
5. `onboarding_bucket_selected` or `onboarding_bucket_created`
6. `onboarding_finish_succeeded`

Breakdowns:

- `onboarding_mode`
- `token_validation_error_type`
- `bucket_count`
- `custom_domain_count`

## Funnel B: First Value (Setup -> First Successful Upload)

Primary question: Does setup lead to a successful upload?

Steps:

1. `onboarding_finish_succeeded` (or `account_exists_on_launch`)
2. `upload_enqueue_requested`
3. `upload_jobs_enqueued`
4. `upload_completed` (first success)

Breakdowns:

- `entrypoint`
- `file_count_bucket`
- `contains_directory`
- `conflict_resolution_used`

## Funnel C: Upload Reliability (Queue -> Terminal Outcome)

Primary question: Where do uploads fail?

Steps:

1. `upload_jobs_enqueued`
2. `upload_processing_cycle_started` (optional)
3. `upload_completed` or `upload_failed`

Key metrics:

- completion rate
- fail rate by `error_type`
- retry success rate
- pause/resume rate
- conflict timeout rate

## Funnel D: Feature Adoption (Power Surfaces)

Measure adoption of:

- Finder right-click flow
- Menu bar drag-and-drop
- Dock file drop
- Deep-link upload
- CLI installation

Events:

- `finder_jobs_transferred`
- `menu_upload_picker_opened`
- `dock_files_received`
- `deep_link_handled` (`host=upload`)
- `cli_install_started` / `cli_install_succeeded`

## Event Naming Conventions

- Use `snake_case`
- Use past tense for completed outcomes (`..._succeeded`, `..._failed`)
- Use present/intent for starts (`..._started`, `..._requested`)
- Keep names stable; change properties instead of renaming events

## Event Catalog (P0 = implement first, P1 = add after base coverage)

Each row lists the recommended placement by file and method.

### Lifecycle / Session

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `app_launch` | App finished launching | `has_accounts`, `activation_policy`, `hide_dock_icon`, `account_count` | `R2Drop/App/R2DropApp.swift:80` `applicationDidFinishLaunching` after config load |
| P0 | `app_services_started` | Core services started | `started_notification_service`, `started_finder_bridge`, `started_upload_monitor`, `started_upload_processor` | `R2Drop/App/R2DropApp.swift:80` after service startup calls |
| P1 | `app_terminate` | App is terminating | `session_duration_sec`, `pending_error_summary_count` | `R2Drop/App/R2DropApp.swift:152` `applicationWillTerminate` |
| P0 | `settings_window_opened` | Settings window brought to front or created | `reason` (`launch`, `menu`, `cmd_comma`, `post_onboarding`, `deeplink`) | `R2Drop/App/R2DropApp.swift:347` `openSettingsWindow` and callers |

### Incoming URLs / External Entry

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `app_open_urls_received` | NSApplication open URLs | `url_count`, `file_url_count`, `deeplink_count` | `R2Drop/App/R2DropApp.swift:172` |
| P0 | `dock_files_received` | Files opened via Dock/Finder open callbacks | `file_count`, `contains_directory` | `R2Drop/App/R2DropApp.swift:187`, `R2Drop/App/R2DropApp.swift:194`, inside `handleIncomingUploadURLs` at `R2Drop/App/R2DropApp.swift:276` |
| P0 | `deeplink_received` | Any `r2drop://` URL | `host`, `path`, `has_query` | `R2Drop/App/DeepLinkHandler.swift:25` before switch |
| P0 | `deeplink_handled` | Deep link returns true | `host`, `route` | `R2Drop/App/DeepLinkHandler.swift:25` after route result |
| P0 | `deeplink_rejected` | Deep link unsupported/invalid | `host`, `reason` | `R2Drop/App/DeepLinkHandler.swift:25` failure branches |

### Onboarding / Account Setup Funnel

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `onboarding_presented` | Onboarding window shown | `onboarding_mode` (`initial`, `add_account`, `update_token`) | `R2Drop/App/R2DropApp.swift:284` `presentOnboardingWindow` |
| P1 | `onboarding_dismissed` | Onboarding window dismissed | `has_accounts_after`, `mode` | `R2Drop/App/R2DropApp.swift:324` `dismissOnboarding` |
| P1 | `onboarding_panel_navigated` | Next/back navigation | `from_panel`, `to_panel`, `direction` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:130`, `R2Drop/App/Onboarding/OnboardingViewModel.swift:139` |
| P0 | `onboarding_skipped` | User skips setup | `panel` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:146` |
| P0 | `onboarding_token_validation_started` | User submits token | `token_length_bucket`, `mode` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:155` before async validation |
| P0 | `onboarding_token_validation_succeeded` | Token validated + accounts/buckets fetched | `mode`, `bucket_count`, `selected_bucket_present`, `custom_domain_prefilled` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:155` success path before `goNext()` |
| P0 | `onboarding_token_validation_failed` | Validation failed | `error_type`, `error_domain`, `error_code`, `user_visible=true` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:228` catch |
| P1 | `onboarding_custom_domains_fetch_started` | Fetch domains for selected bucket | `bucket_hash` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:254` |
| P1 | `onboarding_custom_domains_fetch_succeeded` | Domains fetch returned 200 | `bucket_hash`, `domain_count` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:288` success parse branch |
| P1 | `onboarding_custom_domains_fetch_failed` | Domains fetch non-200 or error | `bucket_hash`, `http_status` or `error_type` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:288`, catch branches |
| P1 | `onboarding_bucket_create_started` | Create new bucket requested | `bucket_name_len` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:345` |
| P1 | `onboarding_bucket_create_succeeded` | Bucket created and refreshed | `bucket_count_after` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:345` success |
| P1 | `onboarding_bucket_create_failed` | Bucket creation fails | `error_type`, `user_visible=true` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:345` catch |
| P0 | `onboarding_finish_started` | User confirms final setup | `mode`, `has_custom_domain`, `path_depth` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:370` |
| P0 | `onboarding_finish_succeeded` | Account persisted successfully | `mode`, `bucket_hash`, `has_custom_domain` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:370` after `AccountManager` save, before celebration |
| P0 | `onboarding_finish_failed` | Save failed | `error_type`, `user_visible=true` | `R2Drop/App/Onboarding/OnboardingViewModel.swift:392` catch |

### Account Management (Existing Users)

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P1 | `accounts_view_loaded` | Accounts list loaded | `account_count`, `has_selection` | `R2Drop/App/Accounts/AccountsViewModel.swift:76` `load()` |
| P1 | `account_selected` | User selects account | `account_name_hash`, `has_custom_domain`, `has_account_id`, `has_token_id` | `R2Drop/App/Accounts/AccountsViewModel.swift:98` |
| P1 | `account_buckets_fetch_succeeded` | Buckets loaded for selected account | `account_name_hash`, `bucket_count` | `R2Drop/App/Accounts/AccountsViewModel.swift:127` Task success |
| P1 | `account_buckets_fetch_failed` | Bucket fetch fails | `account_name_hash`, `error_type` | `R2Drop/App/Accounts/AccountsViewModel.swift:127` catch |
| P1 | `account_custom_domains_refresh_requested` | User clicks refresh domains | `account_name_hash` | `R2Drop/App/Accounts/AccountsViewModel.swift:212` |
| P0 | `account_edit_save_started` | User saves account edits | `renamed`, `bucket_changed`, `path_changed`, `custom_domain_changed` | `R2Drop/App/Accounts/AccountsViewModel.swift:248` |
| P0 | `account_edit_save_succeeded` | Save successful | `renamed`, `has_custom_domain` | `R2Drop/App/Accounts/AccountsViewModel.swift:248` after update true |
| P0 | `account_edit_save_failed` | Save failed / not found | `reason` (`not_found`, `exception`, `validation`) | `R2Drop/App/Accounts/AccountsViewModel.swift:248` failure branches |
| P1 | `account_logout_requested` | User initiates logout from Accounts tab | `account_name_hash`, `surface="accounts_tab"` | `R2Drop/App/Accounts/AccountsViewModel.swift:300` |

### Menu Bar / Finder / Dock Upload Entry Events

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `menu_bar_opened` | Menu opens | `account_count`, `has_active_uploads`, `is_enabled` | `R2Drop/App/MenuBarController.swift:169` `menuWillOpen` |
| P0 | `menu_upload_picker_opened` | User chooses `Upload File(s)...` | `surface="menu_bar"` | `R2Drop/App/MenuBarController.swift:290` |
| P0 | `menu_upload_picker_selection_submitted` | NSOpenPanel accepted | `file_count`, `contains_directory` | `R2Drop/App/MenuBarController.swift:290` after `.OK` |
| P0 | `menu_bar_files_dropped` | Files dropped on status item | `file_count`, `contains_directory`, `is_enabled` | `R2Drop/App/MenuBarController.swift:339` |
| P0 | `upload_confirmation_shown` | Confirmation alert shown | `entrypoint`, `file_count`, `contains_directory`, `never_ask_preexisting` | `R2Drop/App/MenuBarController.swift:378`, `R2Drop/FinderExtension/FinderSync.swift:116`, `R2Drop/App/DeepLinkHandler.swift:83` |
| P0 | `upload_confirmation_result` | Confirmation accepted/cancelled | `entrypoint`, `result`, `never_ask_checked` | same methods as above |
| P1 | `upload_no_active_account_blocked` | Upload flow blocked for no active account | `entrypoint` | `R2Drop/App/MenuBarController.swift:339`, `R2Drop/FinderExtension/FinderSync.swift:60`, `R2Drop/App/DeepLinkHandler.swift:54`, `R2Drop/App/Queue/QueueViewModel.swift:219` |

### Queueing / Conflict Resolution (Main App Worker + Finder Bridge)

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `upload_enqueue_requested` | Start queueing selected URLs | `entrypoint`, `file_count`, `contains_directory`, `account_name_hash`, `bucket_hash` | `R2Drop/App/MenuBarController.swift:406`, `R2Drop/App/Queue/QueueViewModel.swift:219`, `R2Drop/App/DeepLinkHandler.swift:54`, `R2Drop/FinderExtension/FinderSync.swift:185` |
| P0 | `upload_jobs_enqueued` | Queue insert pass completes | `entrypoint`, `jobs_enqueued`, `files_skipped_excluded`, `contains_directory` | `R2Drop/App/MenuBarController.swift:450` worker end, `R2Drop/FinderExtension/FinderSync.swift:185`, `R2Drop/App/DeepLinkHandler.swift:234`, `R2Drop/App/Queue/QueueViewModel.swift:219` |
| P1 | `upload_enqueue_failed` | Queue manager open/insert throws | `entrypoint`, `error_type` | same queueing methods catch/guard failure points |
| P1 | `conflict_check_started` | HEAD check before enqueue | `entrypoint`, `bucket_hash` | `R2Drop/App/MenuBarController.swift:533`, `R2Drop/App/Services/FinderQueueBridge.swift:128` |
| P1 | `conflict_detected` | Existing object found | `entrypoint`, `local_size_bucket`, `remote_size_bucket` | same methods when `headObjectWithTimeout` returns object |
| P1 | `conflict_resolution_applied` | User chooses skip/rename/overwrite | `entrypoint`, `choice`, `apply_to_all` | `R2Drop/App/MenuBarController.swift:533`, `R2Drop/App/Services/FinderQueueBridge.swift:128` |
| P0 | `conflict_check_timeout_or_error` | HEAD returns nil due timeout/error path | `entrypoint`, `timeout_seconds=10` | `R2Drop/App/MenuBarController.swift:571`, `R2Drop/App/Services/FinderQueueBridge.swift:169` |

### Finder Extension + Bridge (Avoid Direct Network Analytics in Extension)

Preferred approach: track Finder usage in the main app via `FinderQueueBridge`. If direct Finder extension analytics is later added, proxy events via App Group storage and flush from main app.

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `finder_queue_transfer_run` | Bridge polls and finds shared jobs | `shared_job_count` | `R2Drop/App/Services/FinderQueueBridge.swift:48` after `sharedJobs` fetch (only when >0) |
| P0 | `finder_jobs_transferred` | Transfer loop completes | `job_count_transferred`, `job_count_skipped`, `job_count_failed`, `had_conflicts` | `R2Drop/App/Services/FinderQueueBridge.swift:48` end of method |
| P1 | `finder_context_menu_clicked` | User clicks "Send to R2" in Finder | `selected_count`, `contains_directory` | `R2Drop/FinderExtension/FinderSync.swift:60` (if implementing extension event proxy) |
| P1 | `finder_extension_no_active_account_blocked` | Finder extension upload blocked | `surface="finder_context_menu"` | `R2Drop/FinderExtension/FinderSync.swift:60` |

### Upload Processing / Engine Invocation

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P1 | `upload_processing_cycle_started` | Rust queue processing invoked | `active_account_hash`, `has_token`, `has_token_id` | `R2Drop/App/Services/UploadProcessor.swift:89` right before detached task creation |
| P0 | `upload_processing_cycle_completed` | Rust process returns | `jobs_processed`, `duration_ms` | `R2Drop/App/Services/UploadProcessor.swift:144` detached task success |
| P0 | `upload_processing_cycle_failed` | Rust process throws | `error_type`, `duration_ms` | `R2Drop/App/Services/UploadProcessor.swift:170` catch |
| P1 | `upload_processing_blocked` | Missing config/active account/token/tokenId | `reason` | `R2Drop/App/Services/UploadProcessor.swift:100`-`139` guard failure branches (dedupe 5 min) |
| P1 | `upload_processing_reentry_skipped` | Timer tick while processing still active beyond timeout threshold | `elapsed_sec` | `R2Drop/App/Services/UploadProcessor.swift:89` timeout log branch (sampled) |

### Upload Outcome / Queue State (Terminal Events Only)

Best place for completion/failure/paused telemetry is `UploadMonitor`, because it already detects transitions and dedupes IDs.

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `upload_completed` | Single completed job transition | `job_id`, `entrypoint` (if available), `bytes_total`, `size_bucket`, `account_name_hash`, `bucket_hash`, `used_custom_domain_url` | `R2Drop/App/Services/UploadMonitor.swift:79` `completedJobs` branch |
| P0 | `upload_batch_completed` | Multiple completed jobs in one poll | `count`, `total_bytes`, `account_count`, `bucket_count` | `R2Drop/App/Services/UploadMonitor.swift:79` batch branch |
| P0 | `upload_failed` | Failed job transition | `job_id`, `bytes_uploaded`, `bytes_total`, `error_type`, `error_message_hash`, `retry_count_if_available` | `R2Drop/App/Services/UploadMonitor.swift:79` `failedJobs` loop |
| P1 | `uploads_paused_detected` | Pause transition heuristic fires | `paused_count`, `reason` (`network_or_manual_unknown`) | `R2Drop/App/Services/UploadMonitor.swift:79` `wasPaused` branch |

### Queue UI Actions (User Controls)

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `queue_pause_requested` | User clicks pause | `job_id`, `status_before` | `R2Drop/App/Queue/QueueViewModel.swift:147` |
| P0 | `queue_resume_requested` | User clicks resume | `job_id`, `status_before` | `R2Drop/App/Queue/QueueViewModel.swift:156` |
| P0 | `queue_cancel_requested` | User clicks cancel | `job_id`, `status_before`, `deferred_delete` | `R2Drop/App/Queue/QueueViewModel.swift:170` |
| P1 | `queue_copy_url_clicked` | User copies URL from queue | `job_id`, `has_custom_domain`, `surface="queue"` | `R2Drop/App/Queue/QueueViewModel.swift:189` |
| P1 | `queue_tab_files_dropped` | Uploads tab drag/drop | `file_count=1`, `contains_directory` | `R2Drop/App/Queue/QueueViewModel.swift:219` |

### Notifications (Delivery + Actions)

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `notification_permission_requested` | Permission request callback | `granted` | `R2Drop/App/Services/NotificationService.swift:50` callback |
| P1 | `notification_posted` | Any notification posted | `category`, `id_prefix` | `R2Drop/App/Services/NotificationService.swift:244` `post(_:id:)` |
| P1 | `notification_upload_complete_shown` | Complete notification requested | `single_or_batch`, `count` | `R2Drop/App/Services/NotificationService.swift:113`, `R2Drop/App/Services/NotificationService.swift:135` |
| P1 | `notification_upload_failed_shown` | Failed notification requested | `job_id` | `R2Drop/App/Services/NotificationService.swift:152` |
| P1 | `notification_token_expired_shown` | Token expired notification requested | `account_name_hash` | `R2Drop/App/Services/NotificationService.swift:179` |
| P0 | `notification_action_clicked` | User clicks notification action | `action` (`copy_url`,`retry`,`setup_token`), `category` | `R2Drop/App/Services/NotificationService.swift:196` |

### Token Validation / Credential Health

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P0 | `token_validation_run_started` | Background validation starts | `account_count` | `R2Drop/App/Services/TokenValidationService.swift:62` |
| P0 | `token_validation_run_completed` | Validation finishes | `account_count`, `valid_count`, `invalid_count`, `duration_ms` | `R2Drop/App/Services/TokenValidationService.swift:62` end |
| P0 | `token_invalid_detected` | Account token invalid | `account_name_hash`, `first_invalid_this_session` | `R2Drop/App/Services/TokenValidationService.swift:62` invalid branch (dedupe per account/day) |
| P1 | `token_validated` | Token valid (summary preferred) | `account_name_hash` | Prefer summary only; if per-account event needed, sample or first-run only at `R2Drop/App/Services/TokenValidationService.swift:62` valid branch |
| P1 | `token_id_backfilled` | Legacy tokenId restored | `account_name_hash` | `R2Drop/App/Services/TokenValidationService.swift:134` |
| P1 | `token_id_backfill_failed` | Backfill persistence fails | `account_name_hash`, `error_type` | `R2Drop/App/Services/TokenValidationService.swift:143` |

### Settings / Preferences / CLI

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P1 | `settings_loaded` | Settings view model loads | `cli_installed`, `hide_dock_icon`, `launch_at_login`, `play_sound`, `concurrent_uploads`, `chunk_size_mb` | `R2Drop/App/Settings/SettingsViewModel.swift:56` end |
| P0 | `setting_changed` | User changes a setting | `setting_key`, `new_value_bucket` | `R2Drop/App/Settings/SettingsViewModel.swift:113`, `134`, `152`, `157`, `164`, `169`, `176`, `181`, `188`, `195`, `201` |
| P0 | `cli_install_started` | User clicks install CLI | `surface="settings"` | `R2Drop/App/Settings/SettingsViewModel.swift:248` |
| P0 | `cli_install_succeeded` | CLI install succeeded | `install_method` (`bundled_binary` or `repo_script`) | `R2Drop/App/Settings/SettingsViewModel.swift:269` result branch |
| P0 | `cli_install_failed` | CLI install failed | `failure_reason` (`no_installer`, `copy_failed`, `script_failed`) | `R2Drop/App/Settings/SettingsViewModel.swift:269` result branch |
| P1 | `cli_detected` | CLI detection finds installed binary | `location` (`/usr/local/bin`, `~/.local/bin`) | `R2Drop/App/Settings/SettingsViewModel.swift:209` |

### Deep Link Actions

| Priority | Event | Trigger | Properties | Placement |
|---|---|---|---|---|
| P1 | `deep_link_upload_requested` | `r2drop://upload` parsed | `compress_requested`, `path_exists`, `readable` | `R2Drop/App/DeepLinkHandler.swift:54` |
| P1 | `deep_link_upload_confirmation_result` | User confirms/cancels deep-link upload | `compress_requested`, `result` | `R2Drop/App/DeepLinkHandler.swift:83` |
| P1 | `deep_link_upload_zip_compress_failed` | ZIP step fails | `error_type` | `R2Drop/App/DeepLinkHandler.swift:96`-`111` |
| P1 | `deep_link_preferences_opened` | `r2drop://preferences` route | `tab` | `R2Drop/App/DeepLinkHandler.swift:127` |
| P1 | `deep_link_account_switch_result` | Account switch success/failure | `result` | `R2Drop/App/DeepLinkHandler.swift:154` |
| P1 | `deep_link_browse_opened` | Browse dashboard route | `account_name_hash`, `bucket_hash` | `R2Drop/App/DeepLinkHandler.swift:175` |
| P1 | `deep_link_auth_setup_opened` | Auth setup wizard opened | `surface="deeplink"` | `R2Drop/App/DeepLinkHandler.swift:201` |

## Error and Issue Telemetry Strategy (No Spam)

## What counts as an error event

Emit `app_error` only for:

- user-visible failures (alerts/errors shown)
- state transition failures (queue insert/update/delete failures)
- network/API failures that block user action
- background service failures that affect uploads

Do **not** emit `app_error` for:

- expected user cancellations
- polling loops with no work
- duplicate transient retries unless first occurrence in dedupe window

### `app_error` event schema (recommended)

Properties:

- `component` (e.g. `onboarding`, `upload_processor`, `finder_queue_bridge`, `cli_install`)
- `operation` (e.g. `validate_token`, `process_queue`, `transfer_job`, `install_cli`)
- `error_type` (Swift type name / custom classifier)
- `error_domain` (if NSError-backed)
- `error_code`
- `error_message_hash`
- `user_visible` (bool)
- `recoverable` (bool)
- `entrypoint` (if relevant)
- `dedupe_key`

### `app_error_summary` event schema

Flush aggregated repeats:

- `window_sec`
- `component`
- `operation`
- `error_type`
- `error_code`
- `repeat_count`
- `first_seen_offset_ms`
- `last_seen_offset_ms`

### High-value issue signals (not raw logs)

Track these as dedicated events (easier product analysis than generic errors):

- `token_invalid_detected`
- `conflict_check_timeout_or_error`
- `upload_processing_blocked`
- `upload_failed`
- `cli_install_failed`
- `notification_permission_requested` (`granted=false`)

## Implementation Placement Notes (Practical)

### 1) Centralize entrypoint tagging

When queueing uploads, attach an internal `entrypoint` context for telemetry emission in the queueing function:

- Menu bar drag: `menu_bar_drag`
- Menu picker: `menu_bar_picker`
- Dock open: `dock_open`
- Queue tab drag: `queue_tab_drag`
- Deep link upload: `deep_link`
- Finder extension transfer: `finder_bridge`

If `UploadJob` is not extended to store entrypoint yet, capture entrypoint at enqueue time and in queue summaries, and accept that terminal upload events may not know the original source in Phase 1.

### 2) Prefer summaries in background services

For:

- `UploadProcessor`
- `FinderQueueBridge`
- `TokenValidationService`

emit one summary per run, plus deduped exceptions.

### 3) Reuse existing debug logging branch points

Many high-value branches already have `R2Log` calls. Those are good instrumentation anchors:

- `OnboardingViewModel` token validation success/failure
- `FinderQueueBridge` transfer outcomes
- `UploadProcessor` process result/error
- `NotificationService` action handlers

## Suggested Rollout Plan

### Phase 0 (Plumbing)

- Add `TelemetryService` wrapper
- Add local config for PostHog host/key
- Add sanitization and dedupe utilities
- Add global context properties

### Phase 1 (P0 catalog only)

Implement P0 events in:

- `R2DropApp`
- `OnboardingViewModel`
- `MenuBarController`
- `FinderQueueBridge`
- `UploadMonitor`
- `UploadProcessor`
- `QueueViewModel`
- `NotificationService`
- `TokenValidationService`
- `SettingsViewModel` (CLI + settings changes)

### Phase 2 (P1 expansion)

- Deep-link route detail events
- Account view fetch metrics
- Finder extension proxied click event
- More granular conflict/fetch events

## PostHog Dashboard Setup (Recommended)

Create these dashboards immediately after implementation:

1. **Activation Funnel**
   - `app_launch` -> `onboarding_presented` -> `onboarding_token_validation_succeeded` -> `onboarding_finish_succeeded`

2. **First Upload Funnel**
   - `onboarding_finish_succeeded` (or `app_launch` with `has_accounts=true`) -> `upload_jobs_enqueued` -> `upload_completed`
   - Breakdown by `entrypoint`

3. **Reliability**
   - `upload_failed` trend
   - `conflict_check_timeout_or_error`
   - `upload_processing_blocked`
   - `token_invalid_detected`

4. **Feature Adoption**
   - `menu_upload_picker_opened`
   - `menu_bar_files_dropped`
   - `dock_files_received`
   - `finder_jobs_transferred`
   - `cli_install_succeeded`

## QA Checklist for Instrumentation Implementation

- Verify no event payload contains raw file paths, bucket names, account names, tokens, `r2Key`, or domains.
- Verify repeated identical errors produce one `app_error` + later `app_error_summary`, not dozens of events.
- Verify `UploadMonitor` emits one terminal event per job transition only.
- Verify `token_invalid_detected` is deduped per account per run/day.
- Verify `entrypoint` values are correct for menu picker, menu drag, Dock drop, deep link, and Finder bridge.
- Verify analytics failures never block UI or uploads.
- Verify telemetry can be disabled (build flag or runtime setting) without touching app logic.

## Notes for AI Implementation Agent

Implementation order (recommended):

1. Create telemetry wrapper + sanitizer + rate limiter
2. Wire service startup in `AppDelegate`
3. Implement P0 lifecycle + onboarding events
4. Implement queueing + upload terminal events
5. Implement error capture helpers and replace selected `catch` branches
6. Implement settings/CLI + notification action events
7. Add unit tests for sanitization/dedupe
8. Add a debug mode that logs telemetry payloads locally before sending

Keep instrumentation changes side-effect-free:

- no throwing from telemetry calls
- no await on UI-critical paths unless fire-and-forget
- always fail open (analytics failure must never break app behavior)
