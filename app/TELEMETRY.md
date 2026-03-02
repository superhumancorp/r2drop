# R2Drop Telemetry

R2Drop collects anonymous usage telemetry via PostHog to improve the app. No personal data, file paths, credentials, or bucket names are ever collected.

## What we collect

All values that could identify you (account names, bucket names, domains, file paths) are hashed locally before sending. We use an install-scoped salt so even hashes can't be correlated across installs.

### Event catalog

#### Lifecycle

| Event | When |
|---|---|
| `app_launch` | App starts |
| `app_services_started` | Core services initialized |
| `app_terminate` | App closes |
| `settings_window_opened` | Settings window opened |

#### Onboarding

| Event | When |
|---|---|
| `onboarding_presented` | Onboarding shown |
| `onboarding_dismissed` | Onboarding dismissed |
| `onboarding_skipped` | User skips setup |
| `onboarding_token_validation_started` | Token submitted |
| `onboarding_token_validation_succeeded` | Token validated |
| `onboarding_token_validation_failed` | Token invalid |
| `onboarding_finish_succeeded` | Account setup completed |
| `onboarding_finish_failed` | Account setup failed |

#### Uploads

| Event | When |
|---|---|
| `upload_enqueue_requested` | Upload queued |
| `upload_jobs_enqueued` | Files added to queue |
| `upload_completed` | Upload finished |
| `upload_batch_completed` | Multiple uploads finished |
| `upload_failed` | Upload failed |
| `upload_confirmation_shown` | Confirmation dialog shown |
| `upload_confirmation_result` | User confirmed or cancelled |

#### Upload entry points

| Event | When |
|---|---|
| `menu_bar_opened` | Menu bar clicked |
| `menu_bar_files_dropped` | Files dropped on menu bar icon |
| `menu_upload_picker_opened` | File picker opened from menu |
| `dock_files_received` | Files opened via Dock |
| `finder_queue_transfer_run` | Finder extension jobs transferred |
| `finder_jobs_transferred` | Finder extension transfer completed |
| `deeplink_received` | `r2drop://` URL received |
| `deeplink_handled` | Deep link processed |

#### Queue actions

| Event | When |
|---|---|
| `queue_pause_requested` | Upload paused |
| `queue_resume_requested` | Upload resumed |
| `queue_cancel_requested` | Upload cancelled |

#### Account management

| Event | When |
|---|---|
| `account_edit_save_started` | Account edit started |
| `account_edit_save_succeeded` | Account edit saved |
| `account_edit_save_failed` | Account edit failed |

#### Settings and CLI

| Event | When |
|---|---|
| `setting_changed` | A setting was changed |
| `cli_install_started` | CLI install initiated |
| `cli_install_succeeded` | CLI installed |
| `cli_install_failed` | CLI install failed |

#### Notifications

| Event | When |
|---|---|
| `notification_permission_requested` | Notification permission asked |
| `notification_action_clicked` | User clicked a notification action |

#### Token health

| Event | When |
|---|---|
| `token_validation_run_completed` | Background token check finished |
| `token_invalid_detected` | An expired or invalid token found |

#### Errors

| Event | When |
|---|---|
| `app_error` | First occurrence of an error |
| `app_error_summary` | Aggregated error count (periodic flush) |

### Common properties on all events

- `session_id` — random UUID per app launch
- `app_version`, `build_number`, `os_version`
- `platform` — always `macOS`

### What we never collect

- API tokens or credentials
- File names or file paths
- Account names, bucket names, or custom domains (hashed only)
- Cloudflare account IDs
- Any content of your files

## Identity

R2Drop generates a random anonymous ID on first launch, stored in your macOS Keychain. This ID is not linked to any Cloudflare account or personal information. It exists only to count unique installs.

## Opting out

Telemetry can be disabled in Settings. When disabled, no events are sent.
