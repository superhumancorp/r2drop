// r2-cli/src/main.rs — R2Drop CLI entry point
// Cross-platform CLI companion sharing r2-core with the macOS app.
// Installed as the `r2drop` binary.

mod accounts;
mod config_cmd;
mod history_cmd;
mod upload;

use clap::Parser;
use r2_core::config::{Account, Config};
use r2_core::credentials;
use r2_core::queue::{JobStatus, QueueDb};
use r2_core::s3::R2Client;

// ---------------------------------------------------------------------------
// Clap CLI definition
// ---------------------------------------------------------------------------

/// R2Drop CLI — upload files to Cloudflare R2 from the terminal
#[derive(Parser, Debug)]
#[command(name = "r2drop", version, about)]
struct Cli {
    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(clap::Subcommand, Debug)]
enum Commands {
    /// Authenticate with Cloudflare R2
    Login(LoginArgs),
    /// Upload a file or folder to R2
    Upload(upload::UploadArgs),
    /// Show daemon health, R2 connectivity, active account, queue summary
    Status(StatusArgs),
    /// Show active upload queue
    Queue(QueueArgs),
    /// Manage Cloudflare R2 accounts
    Accounts(accounts::AccountsArgs),
    /// Read or write config values
    #[command(subcommand)]
    Config(config_cmd::ConfigCmd),
    /// Browse upload history
    History(history_cmd::HistoryArgs),
}

#[derive(clap::Args, Debug)]
pub struct LoginArgs {
    /// API token (for scripting; skips interactive prompt)
    #[arg(long)]
    pub token: Option<String>,
    /// Open the R2Drop app's setup wizard instead of CLI auth
    #[arg(long)]
    pub app: bool,
}

#[derive(clap::Args, Debug)]
struct StatusArgs {
    /// Output as JSON
    #[arg(long)]
    json: bool,
}

#[derive(clap::Args, Debug)]
struct QueueArgs {
    /// Output as JSON
    #[arg(long)]
    json: bool,
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

#[tokio::main]
async fn main() {
    let user_config = Config::load().unwrap_or_default();
    let max_log_files = user_config.preferences.max_log_files as usize;
    let max_log_file_size_mb = user_config.preferences.max_log_file_size_mb as usize;
    if let Err(e) = r2_core::logging::init_logging(max_log_files, max_log_file_size_mb, true) {
        eprintln!("Warning: failed to init logging: {e}");
    }

    let cli = Cli::parse();

    match cli.command {
        Some(Commands::Login(args)) => cmd_login(args).await,
        Some(Commands::Upload(args)) => upload::cmd_upload(args).await,
        Some(Commands::Status(args)) => cmd_status(args).await,
        Some(Commands::Queue(args)) => cmd_queue(args),
        Some(Commands::Accounts(args)) => accounts::cmd_accounts(args).await,
        Some(Commands::Config(cmd)) => config_cmd::cmd_config(cmd),
        Some(Commands::History(args)) => history_cmd::cmd_history(args),
        None => {
            println!("R2Drop CLI v{}", env!("CARGO_PKG_VERSION"));
            println!("Run `r2drop --help` for usage.");
        }
    }
}

// ---------------------------------------------------------------------------
// Login command (FR-010, FR-011, FR-012, FR-013)
// ---------------------------------------------------------------------------

pub async fn cmd_login(args: LoginArgs) {
    // --app flag: trigger the macOS app's auth deep link instead (FR-013)
    if args.app {
        println!("Opening R2Drop app setup wizard...");
        if let Err(e) = open::that("r2drop://auth/setup") {
            eprintln!("Could not open deep link: {e}");
            eprintln!("Make sure R2Drop.app is installed and running.");
        }
        return;
    }

    // Open Cloudflare API tokens page in the default browser (FR-010)
    let cf_url = "https://dash.cloudflare.com/profile/api-tokens";
    println!("Opening Cloudflare API tokens page in your browser...");
    if let Err(e) = open::that(cf_url) {
        eprintln!("Could not open browser: {e}");
        println!("Please visit: {cf_url}");
    }

    // Print inline setup instructions (FR-010)
    println!();
    println!("Create an API token with these permissions:");
    println!("  1. Click \"Create Token\"");
    println!("  2. Select \"Create Custom Token\"");
    println!("  3. Add permission: Account > Cloudflare R2 Storage > Edit");
    println!("  4. Set account resources to your account");
    println!("  5. Click \"Continue to summary\" then \"Create Token\"");
    println!("  6. Copy the token and paste it below");
    println!();

    // Get token: from --token arg (FR-012) or masked interactive prompt (FR-011)
    let token = match args.token {
        Some(t) => t,
        None => match rpassword::prompt_password("Paste your API token: ") {
            Ok(t) => t,
            Err(e) => {
                eprintln!("Error reading token: {e}");
                std::process::exit(1);
            }
        },
    };

    let token = token.trim().to_string();
    if token.is_empty() {
        eprintln!("Error: token cannot be empty.");
        std::process::exit(1);
    }

    // Validate the token against Cloudflare API (FR-011)
    print!("Validating token... ");
    if let Err(e) = R2Client::validate_token(&token).await {
        println!("failed!");
        eprintln!("Error: {e}");
        eprintln!("Please check that you copied the full token.");
        std::process::exit(1);
    }
    println!("valid!");

    // Fetch account info to get account name and ID
    let accounts = match R2Client::list_accounts(&token).await {
        Ok(a) => a,
        Err(e) => {
            eprintln!("Error fetching accounts: {e}");
            std::process::exit(1);
        }
    };

    if accounts.is_empty() {
        eprintln!("Error: no Cloudflare accounts found for this token.");
        std::process::exit(1);
    }

    // Use the first account (most users have one)
    let cf_account = &accounts[0];
    println!("Account: {} ({})", cf_account.name, cf_account.id);

    // Store token in OS keychain (FR-011)
    if let Err(e) = credentials::save_token(&cf_account.name, &token) {
        eprintln!("Error storing token in keychain: {e}");
        std::process::exit(1);
    }
    println!("Token stored in OS keychain.");

    // Update config.toml with the account
    let mut cfg = match Config::load() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error loading config: {e}");
            std::process::exit(1);
        }
    };

    // Add or update the account entry
    if let Some(existing) = cfg.accounts.iter_mut().find(|a| a.name == cf_account.name) {
        existing.account_id = Some(cf_account.id.clone());
    } else {
        cfg.accounts.push(Account {
            name: cf_account.name.clone(),
            account_id: Some(cf_account.id.clone()),
            bucket: String::new(),
            path: String::new(),
            custom_domain: None,
            token_id: None,
        });
    }

    // Set as active account
    cfg.active_account = Some(cf_account.name.clone());

    if let Err(e) = cfg.save() {
        eprintln!("Error saving config: {e}");
        std::process::exit(1);
    }

    println!("Active account set to \"{}\".", cf_account.name);
    println!();
    println!("Login complete! Run `r2drop status` to verify.");
}

// ---------------------------------------------------------------------------
// Status command — daemon health, R2 connectivity, account, queue summary
// ---------------------------------------------------------------------------

async fn cmd_status(args: StatusArgs) {
    let cfg = match Config::load() {
        Ok(c) => c,
        Err(e) => {
            eprintln!("Error loading config: {e}");
            std::process::exit(1);
        }
    };

    let version = env!("CARGO_PKG_VERSION");
    let account_name = cfg.active_account.as_deref().unwrap_or("(none)");
    let account_count = cfg.accounts.len();

    // Daemon health: check if Unix socket exists
    let daemon_running = r2_core::config::config_dir()
        .map(|dir| dir.join("r2drop.sock").exists())
        .unwrap_or(false);

    // R2 connectivity: validate token for active account
    let connectivity = if let Some(ref name) = cfg.active_account {
        match credentials::get_token(name) {
            Ok(token) => match R2Client::validate_token(&token).await {
                Ok(_token_id) => "connected".to_string(),
                Err(e) => format!("error ({e})"),
            },
            Err(_) => "no token in keychain".to_string(),
        }
    } else {
        "no active account".to_string()
    };

    // Queue summary
    let queue_summary = if let Ok(queue) = QueueDb::open_default() {
        [
            JobStatus::Pending,
            JobStatus::Uploading,
            JobStatus::Paused,
            JobStatus::Failed,
        ]
        .iter()
        .map(|s| {
            let n = queue.list_jobs_by_status(*s).map(|j| j.len()).unwrap_or(0);
            (s.as_str().to_string(), n)
        })
        .collect::<Vec<_>>()
    } else {
        vec![]
    };

    if args.json {
        let queue_obj: serde_json::Map<String, serde_json::Value> = queue_summary
            .iter()
            .map(|(s, n)| (s.clone(), serde_json::json!(n)))
            .collect();
        let out = serde_json::json!({
            "version": version,
            "active_account": account_name,
            "accounts_configured": account_count,
            "daemon": if daemon_running { "running" } else { "not running" },
            "r2_connectivity": connectivity,
            "queue": queue_obj,
        });
        println!("{}", serde_json::to_string_pretty(&out).unwrap());
    } else {
        println!("R2Drop CLI v{version}");
        println!("Active account: {account_name}");
        println!("Accounts configured: {account_count}");
        println!(
            "Daemon: {}",
            if daemon_running {
                "running (socket found)"
            } else {
                "not running"
            }
        );
        println!("R2 connectivity: {connectivity}");

        if !queue_summary.is_empty() {
            let parts: Vec<String> =
                queue_summary.iter().map(|(s, n)| format!("{n} {s}")).collect();
            println!("Queue: {}", parts.join(", "));
        }
    }
}

// ---------------------------------------------------------------------------
// Queue command — show active upload queue snapshot
// ---------------------------------------------------------------------------

fn cmd_queue(args: QueueArgs) {
    let queue = match QueueDb::open_default() {
        Ok(q) => q,
        Err(e) => {
            eprintln!("Error opening queue: {e}");
            std::process::exit(1);
        }
    };

    // Collect all non-completed jobs
    let mut jobs = Vec::new();
    for status in [
        JobStatus::Uploading,
        JobStatus::Pending,
        JobStatus::Paused,
        JobStatus::Failed,
    ] {
        jobs.extend(queue.list_jobs_by_status(status).unwrap_or_default());
    }

    if args.json {
        let arr: Vec<serde_json::Value> = jobs
            .iter()
            .map(|j| {
                let pct = if j.total_bytes > 0 {
                    (j.bytes_uploaded * 100) / j.total_bytes
                } else {
                    0
                };
                serde_json::json!({
                    "id": j.id,
                    "file_path": j.file_path,
                    "r2_key": j.r2_key,
                    "bucket": j.bucket,
                    "account_name": j.account_name,
                    "status": j.status.as_str(),
                    "bytes_uploaded": j.bytes_uploaded,
                    "total_bytes": j.total_bytes,
                    "progress_pct": pct,
                })
            })
            .collect();
        println!("{}", serde_json::to_string_pretty(&arr).unwrap());
        return;
    }

    if jobs.is_empty() {
        println!("Upload queue is empty.");
        return;
    }

    println!(
        "{:<5} {:<30} {:<10} {:>10} {:>8}",
        "ID", "FILE", "STATUS", "SIZE", "PROGRESS"
    );
    println!("{}", "-".repeat(68));

    for job in &jobs {
        let name = std::path::Path::new(&job.file_path)
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| job.file_path.clone());
        let display = if name.len() > 28 {
            format!("{}...", &name[..25])
        } else {
            name
        };
        let pct = if job.total_bytes > 0 {
            format!("{}%", (job.bytes_uploaded * 100) / job.total_bytes)
        } else {
            "-".to_string()
        };
        println!(
            "{:<5} {:<30} {:<10} {:>10} {:>8}",
            job.id,
            display,
            job.status.as_str(),
            format_bytes(job.total_bytes),
            pct,
        );
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Format a byte count as a human-readable string (e.g. "2.5 MB").
pub fn format_bytes(bytes: u64) -> String {
    if bytes >= 1_073_741_824 {
        format!("{:.1} GB", bytes as f64 / 1_073_741_824.0)
    } else if bytes >= 1_048_576 {
        format!("{:.1} MB", bytes as f64 / 1_048_576.0)
    } else if bytes >= 1024 {
        format!("{:.1} KB", bytes as f64 / 1024.0)
    } else {
        format!("{bytes} B")
    }
}
