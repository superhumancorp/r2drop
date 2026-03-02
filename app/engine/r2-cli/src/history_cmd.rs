// r2-cli/src/history_cmd.rs — Upload history commands for R2Drop CLI
// Lists and searches completed upload records from ~/.r2drop/history.db.

use r2_core::history::{HistoryDb, HistoryEntry};

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------

/// Arguments for the `r2drop history` command.
#[derive(clap::Args, Debug)]
pub struct HistoryArgs {
    /// Limit output to the first N entries
    #[arg(long)]
    pub limit: Option<usize>,
    /// Filter history by filename (case-insensitive substring)
    #[arg(long)]
    pub search: Option<String>,
    /// Output as JSON
    #[arg(long)]
    pub json: bool,
}

// ---------------------------------------------------------------------------
// Command entry point
// ---------------------------------------------------------------------------

pub fn cmd_history(args: HistoryArgs) {
    let db = match HistoryDb::open_default() {
        Ok(d) => d,
        Err(e) => {
            eprintln!("Error opening history database: {e}");
            std::process::exit(1);
        }
    };

    // Fetch entries: search or list all
    let entries = if let Some(ref query) = args.search {
        db.search(query).unwrap_or_else(|e| {
            eprintln!("Error searching history: {e}");
            std::process::exit(1);
        })
    } else {
        db.list_entries().unwrap_or_else(|e| {
            eprintln!("Error listing history: {e}");
            std::process::exit(1);
        })
    };

    // Apply --limit
    let entries: Vec<&HistoryEntry> = match args.limit {
        Some(n) => entries.iter().take(n).collect(),
        None => entries.iter().collect(),
    };

    // Output
    if args.json {
        print_json(&entries);
    } else {
        print_table(&entries);
    }
}

// ---------------------------------------------------------------------------
// Output formatters
// ---------------------------------------------------------------------------

fn print_json(entries: &[&HistoryEntry]) {
    let arr: Vec<serde_json::Value> = entries
        .iter()
        .map(|e| {
            serde_json::json!({
                "id": e.id,
                "file_name": e.file_name,
                "file_size": e.file_size,
                "r2_key": e.r2_key,
                "bucket": e.bucket,
                "account_name": e.account_name,
                "url": e.url,
                "uploaded_at": e.uploaded_at,
            })
        })
        .collect();
    println!("{}", serde_json::to_string_pretty(&arr).unwrap());
}

fn print_table(entries: &[&HistoryEntry]) {
    if entries.is_empty() {
        println!("No upload history found.");
        return;
    }

    println!(
        "{:<5} {:<30} {:>10} {:<20} {:<20}",
        "ID", "FILE", "SIZE", "UPLOADED", "BUCKET"
    );
    println!("{}", "-".repeat(88));

    for e in entries {
        let name = if e.file_name.len() > 28 {
            format!("{}...", &e.file_name[..25])
        } else {
            e.file_name.clone()
        };
        println!(
            "{:<5} {:<30} {:>10} {:<20} {:<20}",
            e.id,
            name,
            crate::format_bytes(e.file_size),
            &e.uploaded_at,
            &e.bucket,
        );
    }

    println!();
    println!("{} entries", entries.len());
}
