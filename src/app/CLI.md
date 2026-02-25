# R2Drop CLI (`r2drop`)

`r2drop` is the terminal companion for R2Drop.

It lets you authenticate, upload files/folders, inspect queue/history, and script basic workflows for Cloudflare R2.

## Install

### Option 1: Homebrew (assumed available)

```bash
brew install r2drop
```

### Option 2: Quick install (assumed available)

```bash
curl -fsSL https://example.com/install.sh | bash
```

### Option 3: From the R2Drop macOS app

In the app, open `Preferences...` and use the CLI install action.

Notes:

- The app prefers installing to `~/.local/bin/r2drop`
- The app can use a bundled CLI binary (when packaged with one)
- In a local dev checkout, it can fall back to `scripts/install-cli.sh --prefix ~/.local`

### Option 4: Local repo install script (developer)

From this repo:

```bash
./scripts/install-cli.sh --prefix ~/.local
```

The installer script builds `engine/r2-cli` in release mode and installs `r2drop` to `<prefix>/bin`.

## PATH setup (zsh)

If you installed to `~/.local/bin` and `r2drop` is not found:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

## Command Overview

Top-level help:

```text
r2drop [COMMAND]
```

Commands:

- `login` — authenticate with Cloudflare R2
- `upload` — upload a file or folder to R2
- `status` — show daemon health, R2 connectivity, active account, queue summary
- `queue` — show active upload queue
- `accounts` — manage configured accounts
- `config` — read/write supported config values
- `history` — browse upload history

## Authentication

### `r2drop login`

Interactive login:

```bash
r2drop login
```

Scripted login (token passed directly):

```bash
r2drop login --token "$CLOUDFLARE_API_TOKEN"
```

Open the macOS app onboarding instead of CLI auth:

```bash
r2drop login --app
```

What it does:

- Opens Cloudflare API token setup guidance (unless using `--app`)
- Validates the token against Cloudflare
- Stores the token in the OS keychain
- Updates `~/.r2drop/config.toml`
- Sets the active account

Important:

- `login` creates/updates the account entry, but your `bucket` may still need to be configured before uploads work
- If you use the macOS app onboarding, bucket/path/custom-domain setup is handled in the UI

## Uploads

### `r2drop upload [OPTIONS] <PATH>`

Upload a file:

```bash
r2drop upload ./screenshot.png
```

Upload a folder recursively:

```bash
r2drop upload ./dist
```

Compress a file or folder to a ZIP before upload:

```bash
r2drop upload ./build-output --compress
```

Upload using a specific account (instead of the active account):

```bash
r2drop upload ./release.zip --account "Work Account"
```

Flags:

- `--compress` — create a ZIP in temp storage before upload
- `--account <ACCOUNT>` — choose a configured account

Notes:

- Folder uploads are recursive (directory structure is preserved under the folder name)
- The upload command requires a configured account with `account_id` and `bucket`
- Upload progress is printed in the terminal per file

## Status and Queue

### `r2drop status`

Human-readable output:

```bash
r2drop status
```

JSON output (for scripts):

```bash
r2drop status --json
```

Reports:

- CLI version
- Active account
- Number of configured accounts
- Daemon/socket health (if present)
- R2 token connectivity validation
- Queue summary by status (`pending`, `uploading`, `paused`, `failed`)

### `r2drop queue`

Show non-completed queue items:

```bash
r2drop queue
```

JSON output:

```bash
r2drop queue --json
```

The CLI includes current progress fields (`bytes_uploaded`, `total_bytes`, `progress_pct`) when available.

## Account Management

### `r2drop accounts`

List accounts:

```bash
r2drop accounts
```

List accounts as JSON:

```bash
r2drop accounts --json
```

Add an account (reuses login flow):

```bash
r2drop accounts --add
```

Switch active account:

```bash
r2drop accounts --switch "Work Account"
```

Remove an account:

```bash
r2drop accounts --remove "Work Account"
```

Notes:

- `--remove` prompts for confirmation (`yes`)
- Removing an account also deletes the stored keychain token for that account

## Config

### `r2drop config get <KEY>`

```bash
r2drop config get concurrent_uploads
r2drop config get chunk_size_mb --json
```

### `r2drop config set <KEY> <VALUE>`

```bash
r2drop config set concurrent_uploads 6
r2drop config set chunk_size_mb 16
r2drop config set hide_dock_icon true
r2drop config set active_account "Work Account"
```

Supported keys:

- `concurrent_uploads` (1-16)
- `chunk_size_mb` (5-100)
- `launch_at_login` (`true`/`false`)
- `hide_dock_icon` (`true`/`false`)
- `play_sound` (`true`/`false`)
- `follow_symlinks` (`true`/`false`)
- `max_log_files`
- `max_log_file_size_mb`
- `active_account`

## History

### `r2drop history`

Show history:

```bash
r2drop history
```

Limit results:

```bash
r2drop history --limit 20
```

Search by filename substring:

```bash
r2drop history --search screenshot
```

JSON output:

```bash
r2drop history --json
```

## Files, Storage, and Shared State

R2Drop CLI uses the same local config/storage conventions as the app.

### Config directory

Default:

- `~/.r2drop/`

Override with environment variable:

```bash
export R2DROP_HOME=/path/to/custom/r2drop-home
```

### Important files (inside `~/.r2drop/` by default)

- `config.toml` — accounts + preferences
- `history.db` — upload history
- `queue.db` — upload queue state
- `r2drop.sock` — daemon socket (if present)
- `logs/` — rotating application/engine logs

### Credentials

API tokens are not stored in `config.toml`.

- Tokens are stored in the OS keychain
- On macOS, the service name is `com.superhumancorp.r2drop`
- This allows the CLI and app to share credentials on the same machine

## Example `config.toml`

```toml
active_account = "Work Account"

[[accounts]]
name = "Work Account"
account_id = "0123456789abcdef0123456789abcdef"
bucket = "my-r2-bucket"
path = "uploads"
custom_domain = "cdn.example.com"
token_id = "11111111-2222-3333-4444-555555555555"

[preferences]
concurrent_uploads = 4
chunk_size_mb = 8
launch_at_login = false
hide_dock_icon = false
play_sound = true
follow_symlinks = false
allow_anonymous_telemetry = true
```

## Automation Tips

Use `--json` variants for scripts and CI-friendly parsing.

Examples:

```bash
r2drop status --json
r2drop accounts --json
r2drop queue --json
r2drop history --limit 50 --json
```

Open app onboarding from shell scripts (when the app is installed):

```bash
r2drop login --app
```

## Troubleshooting

### `r2drop: command not found`

- Confirm install location (`/usr/local/bin/r2drop` or `~/.local/bin/r2drop`)
- Add `~/.local/bin` to `PATH` if needed

### `No account specified` or `Account not found`

- Run `r2drop accounts`
- Set an active account with `r2drop accounts --switch <name>`

### `has no bucket configured`

- Configure the account in the macOS app onboarding/settings
- Or update `~/.r2drop/config.toml` manually with `bucket` and `path`

### `No token for ...` / keychain errors

- Re-run `r2drop login`
- On macOS, verify Keychain access for `com.superhumancorp.r2drop`

### Rust toolchain errors when building locally

The local install script builds from source and expects a modern Rust stable toolchain.

- Script comment currently expects `rustup` stable `1.93+`
- Use `rustup update stable`

## Related Docs

- `README.md` — product overview and macOS app workflows
- `INSTRUMENTATION.md` — analytics/telemetry plan and event catalog
