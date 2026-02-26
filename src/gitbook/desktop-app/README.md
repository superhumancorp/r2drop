# Desktop App Overview

R2Drop is a native macOS menu bar application. It runs quietly in the background and gives you multiple ways to upload files to your Cloudflare R2 bucket.

{% embed url="https://cdn.r2drop.com/r2drop-recording.mp4" %}
Full end-to-end walkthrough — onboarding, uploading, and getting a public URL
{% endembed %}

{% embed url="https://cdn.r2drop.com/r2drop-2.mp4" %}
App tab overview — Uploads, Accounts, Settings, History, and About
{% endembed %}

---

## App Structure

The R2Drop window has five tabs:

| Tab | Purpose |
|-----|---------|
| **Uploads** | Active queue, pending, in-progress, and completed uploads |
| **Accounts** | Manage R2 bucket connections |
| **Settings** | Performance, file exclusions, CLI, logging |
| **History** | Searchable record of all past uploads |
| **About** | Version info, links, auto-update controls |

---

## Menu Bar Icon

The menu bar icon is your primary interaction point. You can:

- Click it to open the R2Drop window
- Drag files directly onto it to upload immediately
- See a subtle indicator when uploads are in progress

---

## Key Behaviors

**Background uploads** — uploads continue even when the app window is closed or the Mac is on a different screen. You don't need to watch it.

**Auto-clipboard** — when an upload completes, the public URL is automatically copied to your clipboard. No need to navigate to the History tab.

**Shared config with CLI** — all accounts and preferences you configure in the app are instantly available in the CLI, and vice versa.

**Keychain-only credentials** — your Cloudflare API tokens are stored in macOS Keychain. They're never written to config files or sent to our servers.

---

## Sections

- [Upload Methods](upload-methods.md) — right-click, drag-drop, file picker, deep links
- [Queue & History](queue-and-history.md) — track active uploads, browse past uploads
- [Accounts](accounts.md) — add, switch, and remove R2 accounts
- [Settings](settings.md) — configure performance, exclusions, CLI, and logging
