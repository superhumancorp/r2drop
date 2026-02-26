# Privacy Policy

**Effective date:** February 26, 2026
**Published by:** Superhuman Intelligence LLC

---

{% hint style="success" %}
**TL;DR:** The app collects nothing. Your credentials never leave your Mac.
{% endhint %}

---

## What the App Collects

**Nothing.** The R2Drop macOS app and CLI collect no personal data, usage metrics, crash reports, or telemetry of any kind.

There is no phone-home. There is no analytics SDK embedded in the app. The only network requests R2Drop makes are to Cloudflare's API endpoints on your behalf.

---

## Your Cloudflare Credentials

Your Cloudflare API token is:

- Stored exclusively in **macOS Keychain** under service `com.superhumancorp.r2drop`
- Never written to disk in plaintext, config files, or shell history
- Never transmitted to Superhuman Intelligence LLC or any third party other than Cloudflare

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

The R2Drop marketing website may use Cloudflare Web Analytics — a privacy-first, cookieless analytics service that does not track individuals or use persistent identifiers. No third-party tracking cookies are used.

---

## Open Source Verification

R2Drop is fully open source under the MIT License. You can audit every network call the app makes at [github.com/superhumancorp/r2drop](https://github.com/superhumancorp/r2drop).

---

## Contact

Privacy questions? Email [legal@r2drop.app](mailto:legal@r2drop.app) or open an issue on [GitHub](https://github.com/superhumancorp/r2drop/issues).

Full policy: [r2drop.app/privacy/](https://r2drop.app/privacy/)
