# Configuration (config.toml)

R2Drop stores all non-secret configuration in `~/.r2drop/config.toml`.

This file is shared between the macOS app and the CLI. Changes made in the app's Settings tab are reflected here, and vice versa.

---

## Location

Default: `~/.r2drop/config.toml`

Override with environment variable:
```bash
export R2DROP_HOME=/path/to/custom/dir
```

---

## Example config.toml

```toml
active_account = "Work Account"

[[accounts]]
name = "Work Account"
account_id = "0123456789abcdef0123456789abcdef"
bucket = "my-r2-bucket"
path = "uploads"
custom_domain = "cdn.example.com"
token_id = "11111111-2222-3333-4444-555555555555"

[[accounts]]
name = "Personal"
account_id = "abcdef0123456789abcdef0123456789"
bucket = "personal-assets"
path = ""
custom_domain = ""
token_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

[preferences]
concurrent_uploads = 4
chunk_size_mb = 8
launch_at_login = false
hide_dock_icon = false
play_sound = true
follow_symlinks = false
max_log_files = 5
max_log_file_size_mb = 10
```

---

## Account Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Display name for this account |
| `account_id` | Yes | Cloudflare account ID |
| `bucket` | Yes | R2 bucket name |
| `path` | No | Path prefix within the bucket (e.g., `uploads/2026/`) |
| `custom_domain` | No | Custom domain connected to this bucket (e.g., `cdn.example.com`) |
| `token_id` | Yes | Identifier used to look up the API token in Keychain |

**Important:** API tokens are stored in macOS Keychain — not in this file. `token_id` is just a Keychain lookup key.

---

## Preferences

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `concurrent_uploads` | int | 4 | How many files upload in parallel (1–16) |
| `chunk_size_mb` | int | 8 | Multipart upload chunk size in MB (5–100) |
| `launch_at_login` | bool | false | Start R2Drop when macOS logs in |
| `hide_dock_icon` | bool | false | Hide the app from the Dock |
| `play_sound` | bool | true | Play a sound when an upload completes |
| `follow_symlinks` | bool | false | Follow symlinks during folder uploads |
| `max_log_files` | int | 5 | Number of rotated log files to keep |
| `max_log_file_size_mb` | int | 10 | Max size of each log file (MB) |

---

## Other Local Files

| File | Description |
|------|-------------|
| `~/.r2drop/queue.db` | Upload queue state (SQLite) |
| `~/.r2drop/history.db` | Upload history (SQLite) |
| `~/.r2drop/r2drop.sock` | Unix socket for CLI ↔ app communication |
| `~/.r2drop/logs/` | Rotating log files |

All files exist only on your machine — none are synced to R2Drop's servers.

---

## Editing Manually

You can edit `config.toml` directly in any text editor. Changes take effect the next time the app or CLI reads the config.

Use `r2drop config set` for a safer, validated way to change preferences from the terminal.
