## [v0.1.2](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.2) — 2026-06-23

- Fix release notes tracking in release workflow
- Update changelog for bulk upload recovery
- Add GitBook legacy path shim
- Fix GitBook docs root config
- Fix App Store download button routing
- Fix bulk upload queue recovery
- Add comprehensive SEO fixes documentation
- Complete blog post OG image fixes and add SEO health check script
- Fix blog post OG images for better social sharing
- Fix SEO issues and deployment workflow
- Rename build story: 'How I Built R2Drop in 2 Afternoons with Ralph-TUI (Agentic Loop)'
- Rewrite build story with accurate details
- Update Ralph-TUI links to ralph-tui.com
- Fix Ralph-TUI links to correct GitHub repo (subsy/ralph-tui)
- Apply CSS fixes to ALL 14 article pages
- Fix comparison article readability: darker text, table contrast, h2 spacing
- Replace Compare bar with Resources footer column across all pages
- Add 2 more articles to homepage (7 total for balanced layout)
- Fix comparison articles: replace Cyberduck/rclone with R2Client/FlareSync, stagger dates
- Add comparison articles, update roundup with Perplexity competitors
- Restore docs/README.md (main repo documentation)
- Add ROADMAP.md, feedback link, clean up docs
- Replace INSTRUMENTATION.md with simplified TELEMETRY.md
- fix: link Superhuman Intelligence LLC to superhumancorp.com in README
- fix: update X links to @paulpierre, change email to support@r2drop.com
- feat(geo): add 3 GEO-optimized articles, update listings, fix paths
- feat(geo): add llms.txt, allow AI crawlers, update sitemap for GEO
- chore: clarify release signing commands and enforce signed appcast workflow
- fix(sparkle): implement Ed25519 signing for appcast enclosures
- fix(sparkle): fix all 4 blocking auto-update issues
- feat: add SHA-256 checksum verification + update Homebrew formulas
- fix: address all pre-public audit issues (#1-#9)
- fix: remove personal email from beads tracker, gitignore beads.db
- fix: update OG image URL to cdn.r2drop.com/site/og.png
- fix(seo): use resized OG banner (1200x630) across all pages
- feat(seo): add Paul Pierre author credit, fix structured data, improve OG
- fix: update all paths after repo restructure (src/ is now root)
- fix: remove personal Apple ID email from Appfile and CLAUDE.md
- fix: remove PII from CLAUDE.md, update sitemap, add og:image to all pages
- chore: make src/ the repo root, remove art/archive from tracking
- chore: restructure repo — src/ becomes the root
- chore: remove old Orvimo templates, fix privacy, update Homebrew refs
- Reorganize root assets under src and update path references
- Move top-level markdown docs into src/docs
- feat(app): enable Sparkle auto-updates pointing to GitHub Releases
- chore: update changelog for v0.1.1 [skip ci]

---

## Unreleased — 2026-06-23

- fix(app): add bulk Uploads recovery actions for clearing failed upload backlogs, retrying failed uploads, and clearing inactive queued uploads without deleting active uploads.
- perf(app): limit large Uploads backlog rendering and batch queue writes so very large file/folder drops remain recoverable.
- test(app): cover 10,000 failed queued uploads being cleared in one operation while preserving pending and active rows.

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- fix(www): rebuild about page using privacy template layout
- docs: audit and fix documentation accuracy against codebase
- build(release): add local dual-arch DMG lane and make target
- fix: macOS-only docs, --json flag, SHA-256 S3 creds, CI diff-only deploy
- chore: update changelog for v0.1.1 [skip ci]
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): normalize cert password whitespace before validation/import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add legacy PKCS12 fallback for macOS keychain import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): align cert decode/import with preflight validation
- chore: update changelog for v0.1.1 [skip ci]
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- chore: update changelog for v0.1.1 [skip ci]
- ci(release): normalize cert password whitespace before validation/import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add legacy PKCS12 fallback for macOS keychain import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): align cert decode/import with preflight validation
- chore: update changelog for v0.1.1 [skip ci]
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- ci(release): normalize cert password whitespace before validation/import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add legacy PKCS12 fallback for macOS keychain import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): align cert decode/import with preflight validation
- chore: update changelog for v0.1.1 [skip ci]
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- ci(release): add legacy PKCS12 fallback for macOS keychain import
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): align cert decode/import with preflight validation
- chore: update changelog for v0.1.1 [skip ci]
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- ci(release): align cert decode/import with preflight validation
- chore: update changelog for v0.1.1 [skip ci]
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- chore: update changelog for v0.1.1 [skip ci]
- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- ci(release): add preflight validation for signing and secrets
- chore: update changelog for v0.1.1 [skip ci]
- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.1](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.1) — 2026-02-27

- ci(release): avoid tag push on manual run and fix changelog range
- feat(www): rename blog listing to articles, fix all nav links

---

## [v0.1.0](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.0) — 2026-02-27

- perf(ci): only upload changed files to R2 on push
- feat(www): create blog.html articles page, rename Resources to Articles

---

## [v0.1.0](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.0) — 2026-02-26

- fix: use DEVELOPER_ID_CERTIFICATE_P12 in release workflow
- chore: close warning cleanup follow-up issues
- fix: resolve swift6 warnings and rust ffi target mismatch
- chore: add follow-up build warning issues
- build: fix local and ci testflight packaging/upload flow
- chore: replace GIFs with compressed versions (~40% smaller)
- docs: add GIF screencasts to GitBook, update gitignore
- ci: build rust ffi before testflight fastlane
- fix: add FORCE_AUTOMATIC_SIGNING to bypass CI manual signing check
- fix: switch to automatic signing with ASC API key auth in CI
- docs: replace iframe video embeds with YouTube {% embed %} blocks
- chore: gitignore YOUTUBE.md, add Fastlane README and Gemfile.lock
- fix: import both distribution + installer certs for App Store signing
- fix: embed videos via CDN-hosted iframe players instead of raw <video> tags
- fix: install all 3 provisioning profiles (app + finder ext + quick action ext)
- docs: replace {% embed %} video cards with inline <video> players
- build: harden fastlane mac app-store packaging
- docs: add release guide and harden fastlane signing flow
- fix: quote Apple Distribution in xcargs
- build: add local release make targets and fix fastlane xcargs quoting
- fix: use shared xcode schemes in fastlane and ci
- fix: rename testflight lane to avoid action name conflict
- fix: simplify provisioning profile install + re-upload profile secret
- fix: point about docs link to docs subdomain
- feat: add documentation link to about tab
- fix: broaden quick action activation rule for finder selections
- fix: install.sh version resolution + auto-deploy to r2drop.com
- fix: use Apple Distribution cert for TestFlight/App Store workflows
- ci: add TestFlight and App Store workflows
- fix: register quick action as macos action extension
- feat: add Fastlane config for TestFlight and Mac App Store
- feat: add quick action setup status hint in settings
- feat: add finder quick action upload extension
- docs: update publisher attribution to Paul Pierre with GitHub link
- fix: remove src/replit gitlink — excluded via .gitignore
- chore: add art assets, screen recordings, and Xcode project updates
- feat: manual release workflow with Gemini changelog + docs expansion
- docs: add comprehensive GitBook documentation for R2Drop
- feat: rename company to Superhuman Intelligence LLC, add legal pages
- fix: make finder right-click uploads resolve shared config
- feat(www): fix card aspect ratio, expand section copy, clean footer
- feat(www): update 3-col feature cards with local screenshots and parallel uploads content
- feat(www): simplify upload method cards to video + label only
- Revert "feat(www): merge hero + animation into single section, keep 3D model"
- feat(www): merge hero + animation into single section, keep 3D model
- feat(www): major homepage cleanup — remove pricing/overview, add animation, update nav icons
- feat(www): video as true background for Six Ways cards
- fix(www): match video dimensions to original big-card img (170px height)
- fix(www): restore big-card-img-wrapper to fix Six Ways card layout
- fix(www): replace Webflow CDN favicons with local files
- fix(www): replace remaining photo in Upload Without Friction section with video
- fix(www): restore card height, overlay text, replace photo grid with videos
- fix(www): video fills full card, text overlays with transparent gradient
- feat(www): add video backgrounds to Six Ways to Upload cards
- fix(www): restore 3D model SVG path data and remove What is R2Drop section
- feat(www): SEO + GEO optimization for r2drop.com
- fix(www): replace Webflow CDN logo with local r2-logo.png on all pages
- feat(www): rewrite all landing page copy for R2Drop
- feat(www): update all page titles, meta, favicons, and copyright
- feat(www): update favicons, SEO schema, and rewrite all page copy

---

# Changelog

All notable releases of R2Drop are documented here.

New entries are prepended automatically by the release workflow using Gemini-generated notes.

---

## [v0.1.0](https://github.com/superhumancorp/r2drop/releases/tag/v0.1.0) — 2026-02-26

Initial release of R2Drop for macOS.

**Features**

- Native macOS menu bar app — runs quietly in the background
- Finder Sync Extension — right-click any file or folder → *Send to R2*
- Drag files onto the menu bar icon or into the app window to upload
- Parallel multipart uploads (default 4 concurrent, configurable up to 16)
- Resumable uploads — crashes and restarts pick up where they left off
- Automatic retry with exponential backoff (up to 10 retries per job)
- Multi-account support — multiple Cloudflare accounts, each with its own bucket and path
- Public URL auto-copied to clipboard on upload complete
- Custom domain support per account (e.g. `cdn.example.com`)
- Upload history stored locally in SQLite (`~/.r2drop/history.db`)
- File exclusion patterns (`.DS_Store`, `._*`, and other macOS noise excluded by default)
- CLI companion (`r2drop`) — upload from terminal, scripts, and CI pipelines
- Deep link support (`r2drop://`) for automation from Alfred, Raycast, Shortcuts, and shell scripts
- Sparkle auto-updates
- All credentials stored exclusively in macOS Keychain — never written to disk