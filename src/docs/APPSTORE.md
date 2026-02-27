# App Store Metadata — R2Drop

ASO-optimized copy for Mac App Store submission via App Store Connect.
All character limits are enforced per Apple guidelines.

---

## Identity

| Field | Value |
|-------|-------|
| **Bundle ID** | `com.superhumancorp.r2drop` |
| **Primary Category** | Developer Tools |
| **Secondary Category** | Productivity |
| **Age Rating** | 4+ |
| **Price** | Free |
| **Availability** | All countries |

---

## Name

> **Limit: 30 characters**

```
R2Drop: Cloudflare R2 Uploader
```
*(30 chars — exact limit)*

**Alternatives (if rejected):**
```
R2Drop — Cloud File Uploader
```
*(28 chars)*

---

## Subtitle

> **Limit: 30 characters.** Appears below the name in search results and on the product page. Treat as a second keyword field — don't repeat words in the name.

```
Menu Bar Uploads for Developers
```
*(31 chars — trim to:)*

```
Menu Bar Upload for Developers
```
*(30 chars)*

**Alternatives:**
```
S3-Compatible Cloudflare Upload
```
*(31 chars — trim to:)*

```
Upload Files to Any R2 Bucket
```
*(29 chars)*

---

## Promotional Text

> **Limit: 170 characters.** Shown at the top of the description. Can be updated at any time without a new app version — use for announcements, limited offers, new feature highlights.

```
Upload anything to Cloudflare R2 from Finder, your menu bar, or the terminal. CLI included. Your API tokens never leave your Mac.
```
*(130 chars)*

---

## Description

> **Limit: 4,000 characters.** The first ~3 lines appear before the "more" fold — put the hook there. Do not use markdown; plain text only.

```
R2Drop is the fastest way to upload files to Cloudflare R2 from your Mac.

Right-click any file in Finder → Send to R2. Drop files on the menu bar icon. Paste a path in the terminal. All three methods hit the same upload queue, share the same config, and copy the public URL to your clipboard the moment the upload finishes.

No browser. No dashboard. No context switching.

───────────────────────────────────────
UPLOAD YOUR WAY
───────────────────────────────────────

• Finder right-click — select "Send to R2" from the context menu on any file or folder
• Drag to menu bar — drop files directly onto the R2Drop icon
• Drag into app — drop into the Uploads tab for a visual queue
• File picker — browse and select via standard macOS file dialog
• CLI — r2drop upload ./file.png from any terminal or script
• Deep links — trigger uploads from Alfred, Raycast, or Shortcuts via r2drop://

───────────────────────────────────────
BUILT FOR LARGE FILES AND FOLDERS
───────────────────────────────────────

R2Drop uses multipart uploads with a configurable chunk size (5–100 MB) and runs up to 16 parallel streams. Uploading a folder recursively preserves the directory structure. Common junk files (.DS_Store, __MACOSX, .env) are filtered automatically.

───────────────────────────────────────
MULTI-ACCOUNT SUPPORT
───────────────────────────────────────

Add as many Cloudflare accounts and R2 buckets as you need. Switch the active account from the menu bar in one click. Each account has its own bucket, optional path prefix, and optional custom domain for public URLs.

───────────────────────────────────────
SECURE BY DESIGN
───────────────────────────────────────

Your Cloudflare API tokens are stored exclusively in macOS Keychain. They are never written to config files or transmitted to R2Drop's servers. The app is sandboxed and notarized.

───────────────────────────────────────
HISTORY AND SEARCH
───────────────────────────────────────

Every upload is logged with its filename, size, destination, timestamp, and public URL. Search your full history instantly — find and re-copy any URL without re-uploading.

───────────────────────────────────────
CLI COMPANION
───────────────────────────────────────

Install the r2drop CLI from inside the app (Settings → Install CLI). The CLI reads the same config file as the app — no separate setup. Use it in build scripts, CI pipelines, or shell workflows:

  r2drop upload ./dist --compress
  r2drop upload ./screenshot.png

───────────────────────────────────────
PERFORMANCE SETTINGS
───────────────────────────────────────

• Concurrent uploads: 1–16 (default 4)
• Chunk size: 5–100 MB (default 8 MB)
• File exclusion patterns: glob-based, fully customizable

───────────────────────────────────────
AUTOMATIC UPDATES
───────────────────────────────────────

R2Drop uses Sparkle for automatic updates. Toggle auto-check on or off, or check manually from the About tab.

───────────────────────────────────────

R2Drop is open source. Issues and contributions welcome at github.com/superhumancorp/r2drop.
```

*(~2,650 chars — well within 4,000 limit)*

---

## Keywords

> **Limit: 100 characters total.** Comma-separated, no spaces after commas. Do not repeat words already in the name or subtitle — Apple ignores duplicates. Focus on terms users search for.

```
S3,bucket,cloud,CDN,storage,transfer,sync,finder,upload,file manager,developer,AWS,backup,server
```
*(95 chars)*

**Rationale:**
- `S3` — R2 is S3-compatible; many users search this
- `bucket` — natural R2/S3 terminology
- `cloud,CDN,storage,transfer` — broad discoverability
- `sync,backup` — common adjacent searches
- `finder` — macOS integration users search this
- `developer,server` — target audience qualifiers
- `AWS` — captures users evaluating alternatives to S3

---

## What's New (v0.1.0)

> **Limit: 4,000 characters.** Shown in the "Version History" section and as a notification to existing users on update.

```
First release.

• Upload files and folders from Finder, menu bar, or CLI
• Multipart upload engine with configurable concurrency and chunk size
• Multi-account support — manage multiple R2 buckets
• Auto-clipboard: public URL copied on upload completion
• Full upload history with search
• File exclusion patterns for bulk folder uploads
• Keychain-only API token storage
• Automatic updates via Sparkle
```

---

## Support & Legal URLs

| Field | URL |
|-------|-----|
| **Support URL** | `https://r2drop.com` |
| **Marketing URL** | `https://r2drop.com` |
| **Privacy Policy URL** | `https://r2drop.com/privacy` |

---

## App Review Notes

> Paste into the "Notes" field in App Store Connect to help reviewers understand the app.

```
R2Drop is a Cloudflare R2 file uploader for macOS.

To test the app, you need a Cloudflare account with an R2 bucket and an API token scoped to R2:Edit. Cloudflare offers a free tier with generous limits — no payment required for testing.

Setup steps:
1. Create a free Cloudflare account at cloudflare.com
2. Enable R2 (free tier, no credit card required for the trial storage quota)
3. Create an R2 bucket
4. Generate an API token: My Profile → API Tokens → Create Token → Workers R2 Storage:Edit
5. Launch R2Drop and paste the token in the onboarding screen

The Finder extension ("Send to R2") appears in System Settings → Privacy & Security → Extensions → Finder Extensions. It must be enabled manually after installation — this is a macOS requirement for Finder Sync Extensions.

The CLI component (r2drop) is installed optionally from Settings → Install CLI. It is not required for core functionality and does not affect sandbox compliance — it installs to ~/.local/bin via a helper tool.

There is no login, no R2Drop account, and no data sent to our servers. All credentials stay in macOS Keychain.
```

---

## Screenshot Specifications

> Mac App Store requires screenshots at specific sizes. Prepare one set per required size.

| Size | Required | Notes |
|------|----------|-------|
| **1280 × 800** | Yes | 13" MacBook baseline |
| **1440 × 900** | Yes | 15" MacBook baseline |
| **2560 × 1600** | Yes | 13" Retina (2× of 1280×800) |
| **2880 × 1800** | Yes | 15" Retina (2× of 1440×900) |

Up to 10 screenshots per size. Recommended order:
1. Menu bar overview — app in context on a real desktop
2. Finder right-click — "Send to R2" context menu
3. Upload queue — active uploads with progress bars
4. History tab — searchable log with URLs
5. Accounts tab — multi-account setup
6. Settings tab — concurrency and exclusion controls

---

## App Preview Video (Optional)

> 15–30 seconds, MP4, required resolutions: 1080×1920 or 886×1920 (portrait) or 1920×1080 (landscape) for Mac. Autoplay without sound in search results — use motion to tell the story.

Suggested script:
- 0–3s: Finder right-click → Send to R2 (instant reaction)
- 3–8s: Menu bar drag-and-drop
- 8–14s: URL copied to clipboard, notification fires
- 14–20s: History tab search, re-copy URL
- 20–25s: CLI `r2drop upload` running in terminal

---

## Content Rights

- [ ] Does your app contain, display, or access third-party content? **No**
- [ ] Does your app use encryption? **Yes** — HTTPS/TLS for Cloudflare API and R2 upload traffic. Uses standard Apple/OS encryption frameworks only. **Qualifies for ERN exemption** (standard encryption, no export compliance form needed).

---

## Fastlane Deliver Integration

To use this metadata with `fastlane deliver`, create `src/app/fastlane/metadata/en-US/` and populate:

```
fastlane/metadata/en-US/
  name.txt                  ← App name
  subtitle.txt              ← Subtitle
  description.txt           ← Full description
  keywords.txt              ← Comma-separated keywords
  promotional_text.txt      ← Promotional text
  release_notes.txt         ← What's new
  support_url.txt
  marketing_url.txt
  privacy_url.txt
```

Then update the `release_appstore` lane to set `skip_metadata: false`.
