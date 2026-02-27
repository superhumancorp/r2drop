# Authentication

Before uploading, you need to connect a Cloudflare account with an R2 API token.

---

## Interactive Login

Run the login command and follow the prompts:

```bash
r2drop login
```

This will:
1. Guide you to create an API token in the Cloudflare dashboard
2. Prompt you to paste the token
3. Validate the token against Cloudflare's API
4. Store the token in the OS keychain
5. Update `~/.r2drop/config.toml` with account details
6. Set this as the active account

---

## Scripted Login

Pass the token directly (useful in CI/CD or scripts where interactive input isn't possible):

```bash
r2drop login --token "$CLOUDFLARE_API_TOKEN"
```

---

## Launch App Onboarding

If you prefer the guided macOS app onboarding flow (which also handles bucket config):

```bash
r2drop login --app
```

This opens the R2Drop macOS app to the onboarding screen.

---

## Creating the Right API Token

R2Drop needs a token with **R2 Storage write permissions**.

In the [Cloudflare dashboard](https://dash.cloudflare.com):

1. Go to **My Profile → API Tokens → Create Token**
2. Choose a custom token with:
   - **Permissions:** `Workers R2 Storage : Edit`
   - **Account Resources:** your account
3. Optionally restrict to specific R2 buckets for least-privilege access

---

## After Login

You still need to configure your bucket. The `login` command saves the token and creates the account entry, but you may need to set `bucket` before uploads work:

```bash
# Check current account config
r2drop config get active_account
r2drop accounts

# Configure bucket via the macOS app's Accounts tab, or:
# edit ~/.r2drop/config.toml manually
```

---

## Keychain Storage

API tokens are stored in the OS keychain — not in any file.

- **macOS Keychain**, service name `com.superhumancorp.r2drop`

Tokens are never written to `config.toml`, shell history, or environment variables.

---

## Multiple Accounts

Run `r2drop login` again to add a second account. It creates a new entry rather than overwriting the existing one.

See [Accounts](../desktop-app/accounts.md) for managing multiple accounts.
