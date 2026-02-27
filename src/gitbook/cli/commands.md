# Commands

Full reference for all `r2drop` CLI commands.

---

## `r2drop login`

Authenticate with Cloudflare R2.

```bash
r2drop login                          # Interactive
r2drop login --token "$CF_TOKEN"      # Scripted
r2drop login --app                    # Open macOS app onboarding
```

See [Authentication](authentication.md) for full details.

---

## `r2drop upload`

Upload a file or folder to R2.

```bash
r2drop upload <PATH> [OPTIONS]
```

### Examples

```bash
# Upload a single file
r2drop upload ./screenshot.png

# Upload a folder recursively
r2drop upload ./dist

# Compress a folder to ZIP before uploading
r2drop upload ./build-output --compress

# Upload to a specific account
r2drop upload ./release.zip --account "Work CDN"
```

### Flags

| Flag | Description |
|------|-------------|
| `--compress` | Create a ZIP file in temp storage before uploading |
| `--account <NAME>` | Upload using a specific configured account |
| `--json` | Output results as JSON with file paths, URLs, sizes, and status. Useful for piping into `jq` or integrating with scripts. |

### `--json` Output Example

```bash
r2drop upload ./screenshots --json
```

```json
[
  {
    "file": "screenshot.png",
    "key": "uploads/screenshot.png",
    "url": "https://cdn.example.com/uploads/screenshot.png",
    "size": 245760,
    "status": "uploaded"
  }
]
```

### Notes

- Folder uploads are recursive; directory structure is preserved under the folder name
- File exclusion patterns (configured in Settings) are applied during folder uploads
- Upload progress is printed per file in the terminal

---

## `r2drop status`

Show overall system health and connectivity.

```bash
r2drop status           # Human-readable
r2drop status --json    # JSON output
```

Reports:
- CLI version
- Active account name
- Number of configured accounts
- Daemon socket health (if the macOS app is running)
- R2 token connectivity check (live Cloudflare API ping)
- Upload queue summary by status

---

## `r2drop queue`

Show active (non-completed) queue items.

```bash
r2drop queue            # Human-readable
r2drop queue --json     # JSON output
```

Each entry includes file name, status, and progress fields (`bytes_uploaded`, `total_bytes`, `progress_pct`) when available.

---

## `r2drop accounts`

Manage configured R2 accounts.

```bash
r2drop accounts                       # List all accounts
r2drop accounts --json                # JSON output
r2drop accounts --add                 # Add a new account (interactive)
r2drop accounts --switch "Work CDN"   # Set active account
r2drop accounts --remove "Work CDN"   # Remove an account (prompts for confirmation)
```

**Note:** Removing an account also deletes its API token from the OS keychain.

---

## `r2drop config`

Read and write supported configuration values.

### Get a value

```bash
r2drop config get concurrent_uploads
r2drop config get chunk_size_mb --json
```

### Set a value

```bash
r2drop config set concurrent_uploads 6
r2drop config set chunk_size_mb 16
r2drop config set active_account "Work CDN"
r2drop config set hide_dock_icon true
```

### Supported Keys

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `concurrent_uploads` | int (1–16) | 4 | Parallel upload slots |
| `chunk_size_mb` | int (5–100) | 8 | Multipart chunk size |
| `launch_at_login` | bool | false | Start at macOS login |
| `hide_dock_icon` | bool | false | Hide from Dock |
| `play_sound` | bool | true | Sound on upload complete |
| `follow_symlinks` | bool | false | Follow symlinks in folder uploads |
| `max_log_files` | int | 5 | Number of rotated log files to keep |
| `max_log_file_size_mb` | int | 10 | Max size of each log file |
| `active_account` | string | — | Name of the active account |

---

## `r2drop history`

Browse upload history.

```bash
r2drop history                        # Show recent history
r2drop history --limit 20             # Limit results
r2drop history --search screenshot    # Filter by filename
r2drop history --json                 # JSON output
```

---

## Global Flags

These flags work on all commands:

| Flag | Description |
|------|-------------|
| `--json` | Output results as JSON with file paths, URLs, sizes, and status. Useful for piping into `jq` or integrating with scripts. |
| `--help` | Show help for the command |
| `--version` | Show CLI version |
