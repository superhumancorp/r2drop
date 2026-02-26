# Upload Methods

R2Drop supports six ways to upload files. Each one fits a different workflow.

---

## 1. Finder Right-Click

The most natural way to upload on macOS.

1. Right-click any file or folder in Finder
2. Select **Send to R2** from the context menu
3. The upload starts immediately in the background

This works on individual files, multiple selected files, and entire folders.

**Note:** If *Send to R2* doesn't appear in the context menu, go to **System Settings → Privacy & Security → Extensions → Finder Extensions** and ensure the R2Drop extension is enabled.

---

## 2. Drag to Menu Bar

Drop files directly onto the R2Drop icon in your menu bar.

{% embed url="https://youtu.be/FtfqbHIBGBo" %}

This is the fastest method when you already have files open in Finder and want to upload without any clicks.

---

## 3. Drag into the App

Open the R2Drop window and drag files into the **Uploads** tab drop zone.

{% embed url="https://youtu.be/TsWVubTlzoc" %}

The drop zone accepts single files, multiple files, and folders. Folder contents are uploaded recursively, preserving the directory structure.

---

## 4. Menu Bar → Open & Upload

Click the menu bar icon → click the upload/file picker option to open a standard macOS file browser. Select one or more files and they'll be queued immediately.

---

## 5. CLI

Upload from your terminal or scripts:

```bash
r2drop upload ./screenshot.png
r2drop upload ./dist --compress
```

See the full [CLI reference](../cli/commands.md) for all flags and options.

---

## 6. Deep Links

Trigger uploads from other apps using the `r2drop://` URL scheme:

```
r2drop://upload?path=/path/to/file.png
```

This works from Alfred, Raycast, shell scripts, Shortcuts, and any app that can open URLs.

---

## What Gets Uploaded

| Input | Behavior |
|-------|---------|
| Single file | Uploaded as-is |
| Multiple files | Each uploaded individually, in parallel |
| Folder | Contents uploaded recursively; directory structure preserved |
| Folder + `--compress` | Zipped first, then uploaded as a single `.zip` |

Uploads matching exclusion patterns in **Settings → File Exclusion Patterns** are automatically skipped.
