// r2-cli/src/config_cmd.rs — Config get/set commands for R2Drop CLI
// Reads and writes individual keys in ~/.r2drop/config.toml.

use r2_core::config::Config;

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------

/// Arguments for the `r2drop config` command.
#[derive(clap::Subcommand, Debug)]
pub enum ConfigCmd {
    /// Get a config value by key
    Get(GetArgs),
    /// Set a config value
    Set(SetArgs),
}

#[derive(clap::Args, Debug)]
pub struct GetArgs {
    /// Config key (e.g. "concurrent_uploads", "chunk_size_mb")
    pub key: String,
    /// Output as JSON
    #[arg(long)]
    pub json: bool,
}

#[derive(clap::Args, Debug)]
pub struct SetArgs {
    /// Config key
    pub key: String,
    /// Value to set
    pub value: String,
    /// Output as JSON
    #[arg(long)]
    pub json: bool,
}

// ---------------------------------------------------------------------------
// Supported config keys
// ---------------------------------------------------------------------------

/// All writable preference keys. Maps CLI key names to human descriptions.
const KNOWN_KEYS: &[(&str, &str)] = &[
    ("concurrent_uploads", "Parallel upload workers (1-16)"),
    ("chunk_size_mb", "Chunk size in MB (5-100)"),
    ("launch_at_login", "Launch at login (true/false)"),
    ("hide_dock_icon", "Hide dock icon (true/false)"),
    ("play_sound", "Play sound on complete (true/false)"),
    ("follow_symlinks", "Follow symlinks (true/false)"),
    ("max_log_files", "Max rotated log files"),
    ("max_log_file_size_mb", "Max log file size in MB"),
    ("active_account", "Active account name"),
];

// ---------------------------------------------------------------------------
// Command entry point
// ---------------------------------------------------------------------------

pub fn cmd_config(cmd: ConfigCmd) {
    match cmd {
        ConfigCmd::Get(args) => cmd_get(args),
        ConfigCmd::Set(args) => cmd_set(args),
    }
}

// ---------------------------------------------------------------------------
// Get
// ---------------------------------------------------------------------------

fn cmd_get(args: GetArgs) {
    let cfg = load_config();
    let value = read_key(&cfg, &args.key);

    if args.json {
        let out = serde_json::json!({ "key": args.key, "value": value });
        println!("{}", serde_json::to_string_pretty(&out).unwrap());
    } else {
        println!("{}", value);
    }
}

/// Read a config key and return its string representation.
fn read_key(cfg: &Config, key: &str) -> String {
    match key {
        "concurrent_uploads" => cfg.preferences.concurrent_uploads.to_string(),
        "chunk_size_mb" => cfg.preferences.chunk_size_mb.to_string(),
        "launch_at_login" => cfg.preferences.launch_at_login.to_string(),
        "hide_dock_icon" => cfg.preferences.hide_dock_icon.to_string(),
        "play_sound" => cfg.preferences.play_sound.to_string(),
        "follow_symlinks" => cfg.preferences.follow_symlinks.to_string(),
        "max_log_files" => cfg.preferences.max_log_files.to_string(),
        "max_log_file_size_mb" => cfg.preferences.max_log_file_size_mb.to_string(),
        "active_account" => cfg
            .active_account
            .as_deref()
            .unwrap_or("(none)")
            .to_string(),
        _ => {
            eprintln!("Unknown config key: \"{key}\"");
            eprintln!("Available keys:");
            for (k, desc) in KNOWN_KEYS {
                eprintln!("  {k:<25} {desc}");
            }
            std::process::exit(1);
        }
    }
}

// ---------------------------------------------------------------------------
// Set
// ---------------------------------------------------------------------------

fn cmd_set(args: SetArgs) {
    let mut cfg = load_config();
    write_key(&mut cfg, &args.key, &args.value);

    if let Err(e) = cfg.save() {
        eprintln!("Error saving config: {e}");
        std::process::exit(1);
    }

    if args.json {
        let out = serde_json::json!({ "key": args.key, "value": args.value });
        println!("{}", serde_json::to_string_pretty(&out).unwrap());
    } else {
        println!("{} = {}", args.key, args.value);
    }
}

/// Write a value to a config key. Exits on invalid key or value.
fn write_key(cfg: &mut Config, key: &str, value: &str) {
    match key {
        "concurrent_uploads" => {
            cfg.preferences.concurrent_uploads = parse_u8(value, 1, 16);
        }
        "chunk_size_mb" => {
            cfg.preferences.chunk_size_mb = parse_u8(value, 5, 100);
        }
        "launch_at_login" => {
            cfg.preferences.launch_at_login = parse_bool(value);
        }
        "hide_dock_icon" => {
            cfg.preferences.hide_dock_icon = parse_bool(value);
        }
        "play_sound" => {
            cfg.preferences.play_sound = parse_bool(value);
        }
        "follow_symlinks" => {
            cfg.preferences.follow_symlinks = parse_bool(value);
        }
        "max_log_files" => {
            cfg.preferences.max_log_files = parse_u16(value);
        }
        "max_log_file_size_mb" => {
            cfg.preferences.max_log_file_size_mb = parse_u16(value);
        }
        "active_account" => {
            // Validate the account exists
            if !cfg.accounts.iter().any(|a| a.name == value) {
                eprintln!("Account \"{value}\" not found in config.");
                std::process::exit(1);
            }
            cfg.active_account = Some(value.to_string());
        }
        _ => {
            eprintln!("Unknown config key: \"{key}\"");
            eprintln!("Available keys:");
            for (k, desc) in KNOWN_KEYS {
                eprintln!("  {k:<25} {desc}");
            }
            std::process::exit(1);
        }
    }
}

// ---------------------------------------------------------------------------
// Value parsing helpers
// ---------------------------------------------------------------------------

fn parse_u8(s: &str, min: u8, max: u8) -> u8 {
    match s.parse::<u8>() {
        Ok(v) if v >= min && v <= max => v,
        _ => {
            eprintln!("Invalid value: \"{s}\". Expected integer {min}-{max}.");
            std::process::exit(1);
        }
    }
}

fn parse_u16(s: &str) -> u16 {
    s.parse::<u16>().unwrap_or_else(|_| {
        eprintln!("Invalid value: \"{s}\". Expected a positive integer.");
        std::process::exit(1);
    })
}

fn parse_bool(s: &str) -> bool {
    match s.to_lowercase().as_str() {
        "true" | "1" | "yes" | "on" => true,
        "false" | "0" | "no" | "off" => false,
        _ => {
            eprintln!("Invalid value: \"{s}\". Expected true/false.");
            std::process::exit(1);
        }
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
