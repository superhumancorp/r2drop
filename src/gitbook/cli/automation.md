# Automation & CI

The R2Drop CLI is designed to be scriptable. All commands support `--json` output for reliable parsing in scripts and CI pipelines.

---

## JSON Output

Use `--json` for machine-readable output:

```bash
r2drop status --json
r2drop accounts --json
r2drop queue --json
r2drop history --limit 50 --json
r2drop upload ./release.tar.gz --json
```

---

## Shell Script Example

Upload a build artifact and capture the URL:

```bash
#!/bin/bash
set -e

# Build your project
npm run build

# Upload the dist folder
OUTPUT=$(r2drop upload ./dist --json)

# Extract the public URL (requires jq)
URL=$(echo "$OUTPUT" | jq -r '.url')

echo "Deployed to: $URL"
```

---

## GitHub Actions Example

Add `CLOUDFLARE_API_TOKEN` as a GitHub Actions secret, then:

```yaml
name: Deploy Assets

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install r2drop CLI
        run: curl -fsSL https://r2drop.com/install.sh | bash

      - name: Authenticate
        run: r2drop login --token "${{ secrets.CLOUDFLARE_API_TOKEN }}"

      - name: Upload build artifacts
        run: r2drop upload ./dist --account "CI Account"
```

---

## Makefile Example

```makefile
.PHONY: deploy

deploy: build
	r2drop upload ./dist
	@echo "Uploaded to R2"
```

---

## Environment Variables

Override the config directory for isolated CI environments:

```bash
export R2DROP_HOME=/tmp/r2drop-ci
r2drop login --token "$CF_TOKEN"
r2drop upload ./artifacts
```

This keeps CI uploads isolated from your personal `~/.r2drop/` state.

---

## Checking Status Before Uploading

```bash
# Verify connectivity before a critical upload
STATUS=$(r2drop status --json)
if [ "$(echo "$STATUS" | jq -r '.token_valid')" != "true" ]; then
  echo "R2 token is invalid — aborting"
  exit 1
fi

r2drop upload ./release.zip
```

---

## Troubleshooting

### `r2drop: command not found`

The binary is not in your `PATH`. Run:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### `No account specified` or `Account not found`

```bash
r2drop accounts                         # List available accounts
r2drop accounts --switch "My Account"   # Set active account
```

### `has no bucket configured`

Configure the bucket in the macOS app's **Accounts tab**, or edit `~/.r2drop/config.toml` directly.

### `No token for ...` / Keychain errors

```bash
r2drop login   # Re-authenticate
```

On macOS, verify Keychain access for service `com.superhumancorp.r2drop` in Keychain Access.app.
