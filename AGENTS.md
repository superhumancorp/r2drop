# Agent Instructions (Repo Root)

This file is paired with `CLAUDE.md`. Keep both files aligned when release tooling, build paths, or signing policy changes.

## Source of Truth

- Architecture and long-lived context: `CLAUDE.md`
- App-specific task workflow: `app/AGENTS.md`
- Desktop release automation: `.github/workflows/release.yml`
- Local release wrappers: `app/Makefile`

## Release and Sparkle Requirements

- Sparkle appcast must be Ed25519 signed for releases.
- CI release workflow uses Sparkle CLI pinned to `2.9.0`.
- CI requires Sparkle private key secret:
  - preferred: `SPARKLE_ED25519_KEY`
  - legacy fallback: `SPARKLE_PRIVATE_KEY`
- Appcast signing is fail-closed in CI (missing key/signature must fail the release).

## Local Verification Commands

Run from `app/`:

```bash
make release-tools
make release-check-key
make release-verify-update-feed
```

Optional manual signing check:

```bash
make release-sign-dmg DMG=build/R2Drop-<version>-aarch64.dmg
```
