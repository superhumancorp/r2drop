# Privacy Policy

**Effective date:** February 26, 2026
**Published by:** [Paul Pierre](https://github.com/paulpierre)

---

{% hint style="success" %}
**TL;DR:** Telemetry is on by default and fully anonymous. You can opt out any time in Settings. Your credentials and files never leave your Mac.
{% endhint %}

---

## What the App Collects

### Core App

The R2Drop macOS app and CLI collect no personal data. The only network requests R2Drop makes are directly to Cloudflare's API endpoints on your behalf.

### Anonymous Telemetry (On by Default, Opt-Out)

R2Drop sends anonymous usage events to [PostHog](https://posthog.com) — a third-party product analytics service. This is **on by default** and can be disabled at any time in **Settings → Share anonymous usage data**.

**What is sent:**

- App lifecycle events (launch, quit, session duration)
- Feature usage (which upload methods are used, tab interactions)
- Error summaries (type of error, not file contents or paths)
- App version, macOS version, and build number

**What is never sent, even when telemetry is enabled:**

- File names, file contents, or file paths
- Your Cloudflare API token or any credentials
- Bucket names or account names (these are one-way hashed with a per-install salt before transmission — the original values cannot be recovered)
- Upload history or destination URLs

All telemetry events are anonymous. A stable random identifier is generated at install time and stored in macOS Keychain — it is not linked to your name, email, or any other personal information.

**To opt out at any time:** open R2Drop → Settings → toggle **Share anonymous usage data** off.

---

## Your Cloudflare Credentials

Your Cloudflare API token is:

- Stored exclusively in **macOS Keychain** under service `com.superhumancorp.r2drop`
- Never written to disk in plaintext, config files, or shell history
- Never transmitted to Paul Pierre or any third party other than Cloudflare

---

## Your Files

Files you upload with R2Drop travel **directly from your Mac to your Cloudflare R2 bucket**. R2Drop's servers are never in the data path — we cannot see, access, or store your files.

---

## Upload History

R2Drop stores upload history locally in `~/.r2drop/history.db`. This file:

- Exists only on your Mac
- Is never synced to R2Drop's servers
- Can be deleted at any time by removing `~/.r2drop/`

---

## This Website

The R2Drop marketing website uses Google Analytics to understand aggregate traffic patterns. Google Analytics uses cookies. We do not use Meta Pixel or other advertising trackers. You can opt out via your browser settings or the [Google Analytics opt-out extension](https://tools.google.com/dlpage/gaoptout).

---

## Third-Party Services

| Service | Purpose | Data sent | Link |
|---------|---------|-----------|------|
| Cloudflare R2 | File upload destination | Your files (to your own bucket) | [cloudflare.com/privacypolicy](https://www.cloudflare.com/privacypolicy/) |
| PostHog | Anonymous app telemetry (on by default, opt-out) | Anonymous usage events — see above | [posthog.com/privacy](https://posthog.com/privacy/) |
| Google Analytics | Website traffic analytics (website only, not the app) | Page views, referrers (cookies) | [policies.google.com/privacy](https://policies.google.com/privacy) |
| Sparkle | App auto-update checks | Checks GitHub Releases for new versions | Open source, no data sent |

---

## Open Source Verification

R2Drop is fully open source under the MIT License. You can audit every network call the app makes at [github.com/superhumancorp/r2drop](https://github.com/superhumancorp/r2drop).

---

## Contact

Privacy questions? Email [legal@r2drop.com](mailto:legal@r2drop.com) or open an issue on [GitHub](https://github.com/superhumancorp/r2drop/issues).
