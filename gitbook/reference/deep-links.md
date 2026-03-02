# Deep Links (`r2drop://`)

R2Drop registers the `r2drop://` URL scheme on macOS.

This lets you trigger uploads and open specific views from shell scripts, Alfred, Raycast, Shortcuts, and any other app that can open URLs.

---

## Full Reference

| Deep Link | Action |
|-----------|--------|
| `r2drop://upload?path=<absolute_path>` | Queue a file or folder for upload |
| `r2drop://upload?path=<path>&compress=true` | Queue with ZIP compression enabled |
| `r2drop://preferences` | Open the app window (Accounts tab) |
| `r2drop://preferences/queue` | Open → Uploads tab |
| `r2drop://preferences/accounts` | Open → Accounts tab |
| `r2drop://preferences/settings` | Open → Settings tab |
| `r2drop://preferences/history` | Open → History tab |
| `r2drop://preferences/about` | Open → About tab |
| `r2drop://account?name=<name>` | Switch to the named account |
| `r2drop://browse` | Open active account's bucket in Cloudflare dashboard |
| `r2drop://browse?account=<name>` | Open a specific account's bucket in browser |
| `r2drop://auth/setup` | Open the token setup wizard (used by CLI: `r2drop login --app`) |
| `r2drop://status` | Return health info (daemon, R2 connectivity, active account) |

---

## Usage Examples

### Open a URL from the terminal

```bash
open "r2drop://upload?path=/Users/you/Desktop/screenshot.png"
open "r2drop://preferences/history"
open "r2drop://account?name=Work%20CDN"
```

### Alfred / Raycast workflow

Set a custom hotkey that runs:

```
open r2drop://upload?path={selection}
```

Where `{selection}` is the currently selected file in Finder.

### macOS Shortcuts

Use the **Open URLs** action with `r2drop://preferences/queue` to open the upload queue from a keyboard shortcut or menu bar widget.

### Shell script upload trigger

```bash
#!/bin/bash
# Upload the most recently modified file in ~/Desktop
LATEST=$(ls -t ~/Desktop | head -1)
open "r2drop://upload?path=$HOME/Desktop/$LATEST"
```

---

## Security Constraints

Deep links have the following restrictions:

- **Upload links** respect the confirmation dialog unless "Never ask again" is set in Settings
- **Upload links** validate that the path exists and is readable before queuing
- Deep links **cannot** read credentials, exfiltrate account tokens, or modify account settings
- The `r2drop://status` link returns health info but no secret values

---

## CLI Alternative

The CLI provides equivalent scripting without needing deep links:

```bash
r2drop upload /path/to/file.png
r2drop status
r2drop accounts --switch "Work CDN"
```

See the [Commands reference](../cli/commands.md) for full CLI options.
