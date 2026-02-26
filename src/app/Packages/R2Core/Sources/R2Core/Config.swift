// Packages/R2Core/Sources/R2Core/Config.swift
// Config model and TOML reader/writer for ~/.r2drop/config.toml.
// Mirrors the Rust Config struct in r2-core/src/config.rs.
// Both Swift and Rust read/write the same TOML file.

import Foundation

// MARK: - Config Models

/// Top-level config. Matches the Rust `Config` struct.
public struct R2Config: Equatable {
    public var activeAccount: String?
    public var accounts: [ConfigAccount]
    public var preferences: R2Preferences

    public init(
        activeAccount: String? = nil,
        accounts: [ConfigAccount] = [],
        preferences: R2Preferences = R2Preferences()
    ) {
        self.activeAccount = activeAccount
        self.accounts = accounts
        self.preferences = preferences
    }
}

/// A Cloudflare R2 account entry (credentials live in Keychain, not here).
/// Matches the Rust `Account` struct in config.rs.
public struct ConfigAccount: Equatable {
    public var name: String
    public var bucket: String
    public var path: String
    public var customDomain: String?
    /// Cloudflare account ID — used to construct dashboard URLs (FR-040).
    public var accountId: String
    /// Cloudflare API token UUID — used as S3 Access Key ID for R2 uploads.
    /// Retrieved from GET /user/tokens/verify response during onboarding.
    public var tokenId: String

    public init(
        name: String = "",
        bucket: String = "",
        path: String = "",
        customDomain: String? = nil,
        accountId: String = "",
        tokenId: String = ""
    ) {
        self.name = name
        self.bucket = bucket
        self.path = path
        self.customDomain = customDomain
        self.accountId = accountId
        self.tokenId = tokenId
    }
}

/// Global preferences. Matches the Rust `Preferences` struct.
public struct R2Preferences: Equatable {
    public var concurrentUploads: Int
    public var chunkSizeMb: Int
    public var exclusionPatterns: [String]
    public var launchAtLogin: Bool
    public var hideDockIcon: Bool
    public var playSound: Bool
    /// When false (default), symlinks are skipped during upload (FR-051).
    public var followSymlinks: Bool
    /// Maximum number of rotated log files to retain (FR-067).
    public var maxLogFiles: Int
    /// Maximum log file size in MB before rotation cleanup (FR-067).
    public var maxLogFileSizeMb: Int
    /// Allow anonymous telemetry via PostHog (default: false, user must opt in).
    public var allowAnonymousTelemetry: Bool

    public static let defaultExclusions = [
        ".DS_Store", "._*", ".Thumbs.db", ".Spotlight-V100",
        ".Trashes", "__MACOSX", ".fseventsd"
    ]

    public init(
        concurrentUploads: Int = 4,
        chunkSizeMb: Int = 8,
        exclusionPatterns: [String] = R2Preferences.defaultExclusions,
        launchAtLogin: Bool = false,
        hideDockIcon: Bool = false,
        playSound: Bool = true,
        followSymlinks: Bool = false,
        maxLogFiles: Int = 5,
        maxLogFileSizeMb: Int = 10,
        allowAnonymousTelemetry: Bool = false
    ) {
        self.concurrentUploads = concurrentUploads
        self.chunkSizeMb = chunkSizeMb
        self.exclusionPatterns = exclusionPatterns
        self.launchAtLogin = launchAtLogin
        self.hideDockIcon = hideDockIcon
        self.playSound = playSound
        self.followSymlinks = followSymlinks
        self.maxLogFiles = maxLogFiles
        self.maxLogFileSizeMb = maxLogFileSizeMb
        self.allowAnonymousTelemetry = allowAnonymousTelemetry
    }
}

// MARK: - ConfigManager

/// Reads and writes ~/.r2drop/config.toml (or R2DROP_HOME override).
public final class ConfigManager {

    /// Resolve the R2Drop config directory.
    /// Checks R2DROP_HOME env var first, falls back to ~/.r2drop.
    public static func configDir() -> URL {
        if let envPath = ProcessInfo.processInfo.environment["R2DROP_HOME"],
           !envPath.isEmpty {
            return URL(fileURLWithPath: envPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".r2drop")
    }

    /// Full path to config.toml.
    public static func configPath() -> URL {
        configDir().appendingPathComponent("config.toml")
    }

    /// Shared App Group mirror path for config.toml.
    /// Used by sandboxed extensions (Finder Sync) that cannot reliably read ~/.r2drop.
    public static func appGroupConfigPath(appGroup: String = R2CoreConstants.appGroup) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent("config.toml")
    }

    /// Load config from disk. Returns defaults if file doesn't exist.
    public static func load(from path: URL? = nil) throws -> R2Config {
        if let path {
            return try loadExact(from: path)
        }

        do {
            let primary = try loadExact(from: configPath())
            // Sandbox-restricted extensions may see ~/.r2drop as effectively missing.
            // If the primary result is empty, try the App Group mirror before returning defaults.
            if primary == R2Config(),
               let mirrorPath = appGroupConfigPath(),
               let mirrored = try? loadExact(from: mirrorPath),
               mirrored != R2Config() || FileManager.default.fileExists(atPath: mirrorPath.path) {
                return mirrored
            }
            return primary
        } catch {
            // Finder Sync extension runs sandboxed and may not be able to read ~/.r2drop.
            // Fall back to the App Group config mirror if present.
            if let mirrorPath = appGroupConfigPath(),
               let mirrored = try? loadExact(from: mirrorPath) {
                return mirrored
            }
            throw error
        }
    }

    /// Save config to disk as TOML.
    public static func save(_ config: R2Config, to path: URL? = nil) throws {
        let filePath = path ?? configPath()
        try saveExact(config, to: filePath)

        // Best-effort mirror for sandboxed extensions (Finder Sync).
        if path == nil,
           let mirrorPath = appGroupConfigPath(),
           mirrorPath.path != filePath.path {
            try? saveExact(config, to: mirrorPath)
        }
    }

    /// Best-effort sync from ~/.r2drop/config.toml to the App Group mirror.
    /// Safe to call on app launch.
    public static func syncAppGroupMirror() {
        guard let mirrorPath = appGroupConfigPath() else { return }
        guard let config = try? loadExact(from: configPath()) else { return }
        try? saveExact(config, to: mirrorPath)
    }

    private static func loadExact(from filePath: URL) throws -> R2Config {
        guard FileManager.default.fileExists(atPath: filePath.path) else {
            return R2Config()
        }
        let content = try String(contentsOf: filePath, encoding: .utf8)
        return TOMLParser.parse(content)
    }

    private static func saveExact(_ config: R2Config, to filePath: URL) throws {
        if let parent = filePath.deletingLastPathComponent() as URL? {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true
            )
        }
        let toml = TOMLWriter.write(config)
        try toml.write(to: filePath, atomically: true, encoding: .utf8)
    }
}

// MARK: - TOML Parser (handles our specific config format)

/// Parses config.toml produced by Rust's `toml::to_string_pretty()`.
/// Only handles the subset of TOML used by R2Drop config.
enum TOMLParser {

    static func parse(_ content: String) -> R2Config {
        var config = R2Config()
        var section: String?
        var account: ConfigAccount?
        var inArray = false
        var arrayValues: [String] = []

        for raw in content.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Multi-line array continuation
            if inArray {
                if line.contains("]") {
                    let part = line.replacingOccurrences(of: "]", with: "")
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: ","))
                    if !part.isEmpty { arrayValues.append(unquote(part)) }
                    config.preferences.exclusionPatterns = arrayValues
                    inArray = false
                } else {
                    let val = line.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
                    if !val.isEmpty { arrayValues.append(unquote(val)) }
                }
                continue
            }

            // Array of tables: [[accounts]]
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                if let a = account { config.accounts.append(a) }
                section = "accounts"
                account = ConfigAccount()
                continue
            }

            // Table header: [preferences]
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if let a = account { config.accounts.append(a); account = nil }
                section = String(line.dropFirst().dropLast())
                continue
            }

            // Key = value
            guard let eqIdx = line.firstIndex(of: "=") else { continue }
            let key = line[..<eqIdx].trimmingCharacters(in: .whitespaces)
            let val = line[line.index(after: eqIdx)...].trimmingCharacters(in: .whitespaces)

            // Inline array: ["a", "b"]
            if val.hasPrefix("[") && val.hasSuffix("]") {
                let inner = val.dropFirst().dropLast()
                let items = inner.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                    .map { unquote($0) }
                if section == "preferences" && key == "exclusion_patterns" {
                    config.preferences.exclusionPatterns = items
                }
                continue
            }

            // Start of multi-line array
            if val.hasPrefix("[") {
                inArray = true
                arrayValues = []
                let after = val.dropFirst().trimmingCharacters(in: .whitespaces)
                for item in after.components(separatedBy: ",") {
                    let t = item.trimmingCharacters(in: .whitespaces)
                    if !t.isEmpty { arrayValues.append(unquote(t)) }
                }
                continue
            }

            // Scalar: apply to current context
            let str = unquote(val)
            if section == nil {
                if key == "active_account" { config.activeAccount = str }
            } else if section == "accounts" {
                switch key {
                case "name": account?.name = str
                case "bucket": account?.bucket = str
                case "path": account?.path = str
                case "custom_domain": account?.customDomain = str.isEmpty ? nil : str
                case "account_id": account?.accountId = str
                case "token_id": account?.tokenId = str
                default: break
                }
            } else if section == "preferences" {
                switch key {
                case "concurrent_uploads": config.preferences.concurrentUploads = Int(str) ?? 4
                case "chunk_size_mb": config.preferences.chunkSizeMb = Int(str) ?? 8
                case "launch_at_login": config.preferences.launchAtLogin = str == "true"
                case "hide_dock_icon": config.preferences.hideDockIcon = str == "true"
                case "play_sound": config.preferences.playSound = str == "true"
                case "follow_symlinks": config.preferences.followSymlinks = str == "true"
                case "max_log_files": config.preferences.maxLogFiles = Int(str) ?? 5
                case "max_log_file_size_mb": config.preferences.maxLogFileSizeMb = Int(str) ?? 10
                case "allow_anonymous_telemetry": config.preferences.allowAnonymousTelemetry = str == "true"
                default: break
                }
            }
        }
        if let a = account { config.accounts.append(a) }
        return config
    }

    /// Strip surrounding double quotes from a TOML string value.
    private static func unquote(_ s: String) -> String {
        if s.count >= 2 && s.hasPrefix("\"") && s.hasSuffix("\"") {
            return String(s.dropFirst().dropLast())
        }
        return s
    }
}

// MARK: - TOML Writer (produces format compatible with Rust's toml crate)

/// Serializes R2Config to TOML matching Rust's `toml::to_string_pretty()`.
enum TOMLWriter {

    static func write(_ config: R2Config) -> String {
        var lines: [String] = []

        if let active = config.activeAccount {
            lines.append("active_account = \"\(active)\"")
        }

        for acct in config.accounts {
            lines.append("")
            lines.append("[[accounts]]")
            lines.append("name = \"\(acct.name)\"")
            lines.append("bucket = \"\(acct.bucket)\"")
            lines.append("path = \"\(acct.path)\"")
            if let domain = acct.customDomain {
                lines.append("custom_domain = \"\(domain)\"")
            }
            if !acct.accountId.isEmpty {
                lines.append("account_id = \"\(acct.accountId)\"")
            }
            if !acct.tokenId.isEmpty {
                lines.append("token_id = \"\(acct.tokenId)\"")
            }
        }

        let p = config.preferences
        lines.append("")
        lines.append("[preferences]")
        lines.append("concurrent_uploads = \(p.concurrentUploads)")
        lines.append("chunk_size_mb = \(p.chunkSizeMb)")
        lines.append("exclusion_patterns = [")
        for pattern in p.exclusionPatterns {
            lines.append("    \"\(pattern)\",")
        }
        lines.append("]")
        lines.append("launch_at_login = \(p.launchAtLogin)")
        lines.append("hide_dock_icon = \(p.hideDockIcon)")
        lines.append("play_sound = \(p.playSound)")
        lines.append("follow_symlinks = \(p.followSymlinks)")
        lines.append("max_log_files = \(p.maxLogFiles)")
        lines.append("max_log_file_size_mb = \(p.maxLogFileSizeMb)")
        lines.append("allow_anonymous_telemetry = \(p.allowAnonymousTelemetry)")
        lines.append("")

        return lines.joined(separator: "\n")
    }
}
