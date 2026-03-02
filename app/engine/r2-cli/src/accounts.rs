// r2-cli/src/accounts.rs — Account management commands for R2Drop CLI
// Implements: list, --add, --remove, --switch for managing Cloudflare accounts.

use r2_core::config::Config;
use r2_core::credentials;

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------

/// Arguments for the `r2drop accounts` command.
#[derive(clap::Args, Debug)]
pub struct AccountsArgs {
    /// Add a new account (triggers login flow)
    #[arg(long)]
    pub add: bool,
    /// Remove an account by name
    #[arg(long)]
    pub remove: Option<String>,
    /// Switch active account to the given name
    #[arg(long)]
    pub switch: Option<String>,
    /// Output as JSON
    #[arg(long)]
    pub json: bool,
}

// ---------------------------------------------------------------------------
// Command entry point
// ---------------------------------------------------------------------------

/// Execute the accounts command. Routes to list/add/remove/switch based on flags.
pub async fn cmd_accounts(args: AccountsArgs) {
    // --add: trigger login flow (reuse the login command logic)
    if args.add {
        // Delegate to the login flow by invoking it directly
        super::cmd_login(super::LoginArgs {
            token: None,
            app: false,
        })
        .await;
        return;
    }

    let mut cfg = load_config();

    // --remove: remove account by name with confirmation
    if let Some(ref name) = args.remove {
        cmd_remove(&mut cfg, name);
        return;
    }

    // --switch: switch active account
    if let Some(ref name) = args.switch {
        cmd_switch(&mut cfg, name, args.json);
        return;
    }

    // Default: list accounts
    cmd_list(&cfg, args.json);
}

// ---------------------------------------------------------------------------
// Sub-handlers
// ---------------------------------------------------------------------------

/// List all configured accounts.
fn cmd_list(cfg: &Config, json: bool) {
    if json {
        let entries: Vec<serde_json::Value> = cfg
            .accounts
            .iter()
            .map(|a| {
                serde_json::json!({
                    "name": a.name,
                    "bucket": a.bucket,
                    "path": a.path,
                    "custom_domain": a.custom_domain,
                    "account_id": a.account_id,
                    "active": cfg.active_account.as_deref() == Some(&a.name),
                })
            })
            .collect();
        println!("{}", serde_json::to_string_pretty(&entries).unwrap());
        return;
    }

    if cfg.accounts.is_empty() {
        println!("No accounts configured. Run `r2drop accounts --add` to set one up.");
        return;
    }

    let active = cfg.active_account.as_deref().unwrap_or("");
    for a in &cfg.accounts {
        let marker = if a.name == active { " *" } else { "" };
        let bucket = if a.bucket.is_empty() {
            "(no bucket)".to_string()
        } else {
            a.bucket.clone()
        };
        println!("  {}{marker}  bucket={bucket}", a.name);
    }
    println!();
    println!("* = active account");
}

/// Remove an account by name. Deletes keychain token and config entry.
fn cmd_remove(cfg: &mut Config, name: &str) {
    let idx = cfg.accounts.iter().position(|a| a.name == name);
    if idx.is_none() {
        eprintln!("Account \"{name}\" not found.");
        std::process::exit(1);
    }

    // Prompt for confirmation
    println!("Remove account \"{name}\"? This will delete the stored token.");
    println!("Type 'yes' to confirm:");
    let mut input = String::new();
    if std::io::stdin().read_line(&mut input).is_err() || input.trim() != "yes" {
        println!("Cancelled.");
        return;
    }

    // Remove keychain token (best-effort; might already be gone)
    if let Err(e) = credentials::delete_token(name) {
        eprintln!("Warning: could not remove keychain token: {e}");
    }

    // Remove from config
    cfg.accounts.remove(idx.unwrap());

    // If removed account was active, clear active_account
    if cfg.active_account.as_deref() == Some(name) {
        cfg.active_account = cfg.accounts.first().map(|a| a.name.clone());
    }

    if let Err(e) = cfg.save() {
        eprintln!("Error saving config: {e}");
        std::process::exit(1);
    }

    println!("Account \"{name}\" removed.");
}

/// Switch the active account.
fn cmd_switch(cfg: &mut Config, name: &str, json: bool) {
    if !cfg.accounts.iter().any(|a| a.name == name) {
        eprintln!("Account \"{name}\" not found.");
        std::process::exit(1);
    }

    cfg.active_account = Some(name.to_string());

    if let Err(e) = cfg.save() {
        eprintln!("Error saving config: {e}");
        std::process::exit(1);
    }

    if json {
        let out = serde_json::json!({ "active_account": name });
        println!("{}", serde_json::to_string_pretty(&out).unwrap());
    } else {
        println!("Active account set to \"{name}\".");
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn load_config() -> Config {
    Config::load().unwrap_or_else(|e| {
        eprintln!("Error loading config: {e}");
        std::process::exit(1);
    })
}
