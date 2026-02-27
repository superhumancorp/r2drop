# YouTube Upload Metadata — R2Drop Documentation Videos

These are unlisted YouTube videos used in the R2Drop GitBook documentation.
Upload each as **Unlisted** so they're embeddable but not publicly searchable.

After uploading, replace each `{% embed url="..." %}` placeholder in the GitBook
markdown files with the actual YouTube URL.

---

## 1. `r2drop-recording.mp4`

**Used in:** `src/gitbook/desktop-app/README.md` (first video)

**Title:**
```
R2Drop — macOS Menu Bar App Overview
```

**Description:**
```
A quick overview of R2Drop, a native macOS menu bar app for uploading files and folders to Cloudflare R2 storage. See how it runs silently in the background, uploads in parallel, and copies the public URL to your clipboard automatically.

Learn more at https://r2drop.com
Documentation: https://docs.r2drop.com
```

**Tags:**
```
R2Drop, Cloudflare R2, macOS, file upload, cloud storage, menu bar app, S3 upload, developer tools
```

**Category:** Science & Technology
**Privacy:** Unlisted

**Markdown embed (paste after uploading):**
```
{% embed url="https://www.youtube.com/watch?v=REPLACE_ME" %}
```

---

## 2. `r2drop-2.mp4`

**Used in:** `src/gitbook/desktop-app/README.md` (second video)

**Title:**
```
R2Drop — App Interface Walkthrough (Uploads, Accounts, Settings, History, About)
```

**Description:**
```
A walkthrough of R2Drop's five tabs: Uploads (active queue), Accounts (R2 bucket connections), Settings (performance and exclusions), History (searchable upload log), and About (version and auto-updates).

Learn more at https://r2drop.com
Documentation: https://docs.r2drop.com
```

**Tags:**
```
R2Drop, Cloudflare R2, macOS app, file upload, cloud storage, S3, developer tools, UI walkthrough
```

**Category:** Science & Technology
**Privacy:** Unlisted

**Markdown embed (paste after uploading):**
```
{% embed url="https://www.youtube.com/watch?v=REPLACE_ME" %}
```

---

## 3. `r2drop-1.mp4`

**Used in:** `src/gitbook/getting-started/first-upload.md` (intro video)

**Title:**
```
R2Drop — Getting Started: First Upload to Cloudflare R2
```

**Description:**
```
How to connect R2Drop to your Cloudflare R2 bucket and upload your first file. Covers creating an API token in the Cloudflare dashboard, running the onboarding flow, configuring your bucket, and getting the public URL after upload.

Learn more at https://r2drop.com
Documentation: https://docs.r2drop.com/getting-started/first-upload
```

**Tags:**
```
R2Drop, Cloudflare R2, getting started, first upload, macOS, cloud storage, API token, S3, tutorial
```

**Category:** Science & Technology
**Privacy:** Unlisted

**Markdown embed (paste after uploading):**
```
{% embed url="https://www.youtube.com/watch?v=REPLACE_ME" %}
```

---

## 4. `r2drop-drag-drop-menu-bar.mp4`

**Used in:** `src/gitbook/desktop-app/upload-methods.md` and `src/gitbook/getting-started/first-upload.md`

**Title:**
```
R2Drop — Drag Files to the Menu Bar Icon
```

**Description:**
```
The fastest way to upload from macOS: drag any file or folder directly onto the R2Drop icon in your menu bar. The upload starts immediately in the background and the public URL is copied to your clipboard when done.

Learn more at https://r2drop.com
Documentation: https://docs.r2drop.com/desktop-app/upload-methods
```

**Tags:**
```
R2Drop, Cloudflare R2, drag and drop, menu bar, macOS, file upload, cloud storage, S3
```

**Category:** Science & Technology
**Privacy:** Unlisted

**Markdown embed (paste after uploading):**
```
{% embed url="https://www.youtube.com/watch?v=REPLACE_ME" %}
```

---

## 5. `r2drop-drag-drop-app.mp4`

**Used in:** `src/gitbook/desktop-app/upload-methods.md` and `src/gitbook/getting-started/first-upload.md`

**Title:**
```
R2Drop — Drag Files into the App Window
```

**Description:**
```
Drop files or folders directly into R2Drop's Uploads tab. The drop zone accepts single files, multiple files, and entire folders. Folder contents are uploaded recursively, preserving the directory structure.

Learn more at https://r2drop.com
Documentation: https://docs.r2drop.com/desktop-app/upload-methods
```

**Tags:**
```
R2Drop, Cloudflare R2, drag and drop, macOS, file upload, cloud storage, folder upload, S3
```

**Category:** Science & Technology
**Privacy:** Unlisted

**Markdown embed (paste after uploading):**
```
{% embed url="https://www.youtube.com/watch?v=REPLACE_ME" %}
```

---

## 6. `r2drop-3.mp4`

**Used in:** `src/gitbook/desktop-app/settings.md`

**Title:**
```
R2Drop — Settings Tab: Upload Performance, Exclusions, CLI, and Configuration
```

**Description:**
```
A walkthrough of R2Drop's Settings tab. Covers concurrent upload and chunk size controls, file exclusion patterns (auto-skip .DS_Store and build artifacts), CLI installation, and config/log directory paths.

Learn more at https://r2drop.com
Documentation: https://docs.r2drop.com/desktop-app/settings
```

**Tags:**
```
R2Drop, Cloudflare R2, settings, macOS, file upload, CLI, configuration, S3, developer tools
```

**Category:** Science & Technology
**Privacy:** Unlisted

**Markdown embed (paste after uploading):**
```
{% embed url="https://www.youtube.com/watch?v=REPLACE_ME" %}
```

---

## After Uploading

For each video, replace the current `<iframe ...>` block in the markdown with:

```
{% embed url="https://www.youtube.com/watch?v=YOUR_VIDEO_ID" %}
```

Files to update:
- `src/gitbook/getting-started/first-upload.md` — videos 3, 4, 5
- `src/gitbook/desktop-app/README.md` — videos 1, 2
- `src/gitbook/desktop-app/upload-methods.md` — videos 4, 5
- `src/gitbook/desktop-app/settings.md` — video 6
