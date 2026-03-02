# Troubleshooting

Common issues and how to fix them.

---

## Finder

### "Send to R2" is missing from the right-click menu

Finder Sync extensions are cached aggressively by macOS.

1. Go to **System Settings → Privacy & Security → Extensions → Finder Extensions**
2. Toggle the R2Drop extension **off**, then back **on**
3. Run `killall Finder` in Terminal

If it still doesn't appear, quit R2Drop completely and relaunch it.

---

## Upload Issues

### Uploads are stuck on "Pending"

- Check that your account has a **bucket configured** — open the Accounts tab and verify the bucket field is not empty
- Check R2 connectivity: `r2drop status`
- If the macOS app is not running, the upload engine won't process the queue — launch the app

### Upload failed with a network error

R2Drop retries automatically with exponential backoff (up to 10 retries). If all retries fail:

1. Check your internet connection
2. Verify your API token is still valid: `r2drop status`
3. Re-run the upload

### `has no bucket configured`

Open **Accounts tab** in the app and fill in the **Bucket** field for your account.

From the CLI, edit `~/.r2drop/config.toml` and set the `bucket` field under the relevant `[[accounts]]` entry.

---

## Authentication

### `No token for ...` / Keychain errors

Your API token was not found in the macOS Keychain.

```bash
r2drop login   # Re-authenticate interactively
```

If issues persist, open **Keychain Access.app**, search for `com.superhumancorp.r2drop`, and delete any stale entries before logging in again.

### Token expired or revoked

R2Drop checks token validity on launch. If the token has been revoked in the Cloudflare dashboard:

1. Create a new API token in [Cloudflare → My Profile → API Tokens](https://dash.cloudflare.com/profile/api-tokens)
2. Run `r2drop login` and paste the new token, or use **Accounts tab → Update Token**

---

## CLI

### `r2drop: command not found`

The binary is not in your `PATH`.

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

Verify the install:

```bash
r2drop --version
```

### `No account specified` or `Account not found`

```bash
r2drop accounts                         # List configured accounts
r2drop accounts --switch "My Account"   # Set active account
```

### Rust toolchain errors when building from source

The install script builds from source and requires a modern Rust stable toolchain.

```bash
rustup update stable
./scripts/install-cli.sh --prefix ~/.local
```

---

## App Behavior

### R2Drop doesn't appear in the Dock

If you've enabled **Hide Dock Icon** in Settings, the app only shows in the menu bar. To restore the Dock icon:

1. Click the menu bar icon → **Preferences → Settings**
2. Uncheck **Hide Dock Icon**

Or from the CLI:

```bash
r2drop config set hide_dock_icon false
```

### No sound on upload complete

Check that **Play sound on complete** is enabled in **Settings tab**, and that your Mac's volume is not muted.

### Auto-updates not working

Open **About tab → Check Now** to manually trigger an update check.

If updates are blocked, verify that R2Drop has outbound network access in **System Settings → Network → Firewall**.

---

## Resetting R2Drop

To start fresh and reset all local state:

```bash
rm -rf ~/.r2drop
```

This removes all accounts, queue, history, and config. Your files in R2 are not affected.

You'll need to go through onboarding again after this.

---

## Still Stuck?

Open an issue on [GitHub](https://github.com/superhumancorp/r2drop/issues) with:
- Your macOS version
- R2Drop version (from **About tab**)
- Steps to reproduce
- Any relevant output from `r2drop status --json`
