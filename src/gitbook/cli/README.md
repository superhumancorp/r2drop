# CLI Overview

`r2drop` is the terminal companion for the R2Drop macOS app.

It lets you upload files and folders, manage accounts, inspect the upload queue, and automate uploads from scripts and CI pipelines — all using the same Cloudflare credentials and config as the desktop app.

---

## Key Features

- Upload files and folders from any terminal
- Script uploads in shell scripts, Makefiles, and CI workflows
- JSON output (`--json`) for machine-readable parsing
- Share accounts and config with the macOS app — no duplicate setup
- Runs on macOS (Apple Silicon and Intel)
- `--json` flag for structured output — pipe into `jq` or integrate with scripts

---

## Quick Reference

```bash
r2drop login              # Authenticate with Cloudflare
r2drop upload <path>      # Upload a file or folder
r2drop status             # Show daemon and connectivity status
r2drop queue              # View active upload queue
r2drop accounts           # Manage configured accounts
r2drop history            # Browse upload history
r2drop config get/set     # Read and write config values
```

---

## Sections

- [Installation](installation.md) — Homebrew, curl, app, or from source
- [Authentication](authentication.md) — connect a Cloudflare account
- [Commands](commands.md) — full command and flag reference
- [Automation & CI](automation.md) — scripts, JSON output, CI examples
