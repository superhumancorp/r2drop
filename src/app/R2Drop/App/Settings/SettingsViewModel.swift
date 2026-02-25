// R2Drop/App/Settings/SettingsViewModel.swift
// ViewModel for the Settings tab in Preferences (US-019).
// Loads/saves preferences from config.toml via ConfigManager.
// Handles Launch at Login (SMAppService), dock icon visibility,
// CLI install detection, and hotkey recording.

import SwiftUI
import R2Core
import ServiceManagement

@MainActor
final class SettingsViewModel: ObservableObject {

    // MARK: - Toggles (FR-045)

    @Published var hideDockIcon: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var playSound: Bool = true

    // MARK: - Upload Performance (FR-048)

    @Published var concurrentUploads: Int = 4
    @Published var chunkSizeMb: Int = 8

    // MARK: - Exclusion Patterns (FR-049)

    @Published var exclusionPatterns: [String] = R2Preferences.defaultExclusions

    // MARK: - Symlink (FR-051)

    @Published var followSymlinks: Bool = false

    // MARK: - Hotkey (FR-047)

    @Published var hotkeyDisplay: String = ""

    // MARK: - CLI Install (FR-046)

    @Published var cliInstalled: Bool = false
    @Published var cliVersion: String = ""
    @Published var cliInstallStatus: String = ""

    // MARK: - Config Directory (FR-050)

    @Published var configDirPath: String = ""

    // MARK: - Logging (FR-067)

    @Published var maxLogFiles: Int = 5
    @Published var maxLogFileSizeMb: Int = 10
    @Published var logDirPath: String = ""

    // MARK: - Lifecycle

    /// Load preferences from config.toml and detect CLI state.
    func load() {
        #if DEBUG
        R2Log.ui.debug("SettingsViewModel.load begin")
        #endif
        let config = (try? ConfigManager.load()) ?? R2Config()
        let prefs = config.preferences

        hideDockIcon = prefs.hideDockIcon
        launchAtLogin = prefs.launchAtLogin
        playSound = prefs.playSound
        concurrentUploads = prefs.concurrentUploads
        chunkSizeMb = prefs.chunkSizeMb
        exclusionPatterns = prefs.exclusionPatterns
        followSymlinks = prefs.followSymlinks
        maxLogFiles = prefs.maxLogFiles
        maxLogFileSizeMb = prefs.maxLogFileSizeMb
        configDirPath = ConfigManager.configDir().path
        logDirPath = ConfigManager.configDir().appendingPathComponent("logs").path

        detectCLI()
        #if DEBUG
        R2Log.ui.debug("SettingsViewModel.load complete")
        #endif
    }

    // MARK: - Save

    /// Persist all preferences to config.toml.
    func save() {
        do {
            #if DEBUG
            R2Log.ui.debug("SettingsViewModel.save begin")
            #endif
            var config = try ConfigManager.load()
            config.preferences.hideDockIcon = hideDockIcon
            config.preferences.launchAtLogin = launchAtLogin
            config.preferences.playSound = playSound
            config.preferences.concurrentUploads = concurrentUploads
            config.preferences.chunkSizeMb = chunkSizeMb
            config.preferences.exclusionPatterns = exclusionPatterns
            config.preferences.followSymlinks = followSymlinks
            config.preferences.maxLogFiles = maxLogFiles
            config.preferences.maxLogFileSizeMb = maxLogFileSizeMb
            try ConfigManager.save(config)
            #if DEBUG
            R2Log.ui.debug("SettingsViewModel.save success")
            #endif
        } catch {
            #if DEBUG
            R2Log.ui.debug("SettingsViewModel.save failed: \(error)")
            #endif
        }
    }

    // MARK: - Launch at Login (FR-045)

    /// Toggle Launch at Login via SMAppService (macOS 13+).
    func toggleLaunchAtLogin(_ enabled: Bool) {
        launchAtLogin = enabled
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            do {
                if enabled {
                    try service.register()
                } else {
                    try service.unregister()
                }
            } catch {
                // Revert on failure
                launchAtLogin = !enabled
            }
        }
        save()
    }

    // MARK: - Hide Dock Icon (FR-045)

    /// Toggle dock icon visibility by switching activation policy.
    func toggleHideDockIcon(_ hide: Bool) {
        #if DEBUG
        R2Log.ui.debug("toggleHideDockIcon=\(hide)")
        #endif
        hideDockIcon = hide
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        save()
        // Re-activate our settings window after policy change.
        // Switching to .accessory hides all windows — we need to bring ours back.
        if hide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                AppDelegate.openSettingsWindow()
            }
        }
    }

    // MARK: - Simple Toggle Saves

    func togglePlaySound(_ enabled: Bool) {
        playSound = enabled
        save()
    }

    func toggleFollowSymlinks(_ enabled: Bool) {
        followSymlinks = enabled
        save()
    }

    // MARK: - Upload Performance (FR-048)

    func updateConcurrentUploads(_ value: Int) {
        concurrentUploads = max(1, min(16, value))
        save()
    }

    func updateChunkSize(_ value: Int) {
        chunkSizeMb = max(5, min(100, value))
        save()
    }

    // MARK: - Logging (FR-067)

    func updateMaxLogFiles(_ value: Int) {
        maxLogFiles = max(1, min(50, value))
        save()
    }

    func updateMaxLogFileSizeMb(_ value: Int) {
        maxLogFileSizeMb = max(1, min(100, value))
        save()
    }

    // MARK: - Exclusion Patterns (FR-049)

    func addExclusionPattern(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !exclusionPatterns.contains(trimmed) else { return }
        exclusionPatterns.append(trimmed)
        save()
    }

    func removeExclusionPattern(at index: Int) {
        guard exclusionPatterns.indices.contains(index) else { return }
        exclusionPatterns.remove(at: index)
        save()
    }

    func resetExclusionPatterns() {
        exclusionPatterns = R2Preferences.defaultExclusions
        save()
    }

    // MARK: - CLI Detection (FR-046)

    /// Check if r2drop CLI is installed at /usr/local/bin or ~/.local/bin.
    func detectCLI() {
        let systemPath = "/usr/local/bin/r2drop"
        let localPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/bin/r2drop").path
        if FileManager.default.fileExists(atPath: systemPath) {
            cliInstalled = true
            cliVersion = getCLIVersion(at: systemPath)
        } else if FileManager.default.fileExists(atPath: localPath) {
            cliInstalled = true
            cliVersion = getCLIVersion(at: localPath)
        } else {
            cliInstalled = false
            cliVersion = ""
        }
    }

    /// Run `r2drop --version` to get the installed CLI version.
    private func getCLIVersion(at path: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return output
        } catch {
            return "unknown"
        }
    }

    /// Install the CLI by running the install script.
    /// Shows status messages and refreshes detection after completion.
    func installCLI() {
        #if DEBUG
        R2Log.ui.debug("installCLI begin")
        #endif
        cliInstallStatus = "Installing..."

        Task.detached {
            let (_, statusMessage) = Self.installCLIInBackground()

            await MainActor.run { [weak self] in
                #if DEBUG
                R2Log.ui.debug("installCLI result: \(statusMessage)")
                #endif
                self?.cliInstallStatus = statusMessage
                self?.detectCLI()
            }
        }
    }

    // MARK: - CLI Install Helpers

    private nonisolated static func installCLIInBackground() -> (Bool, String) {
        let installPrefix = userLocalPrefixPath()
        let installDir = URL(fileURLWithPath: installPrefix, isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
        let destination = installDir.appendingPathComponent("r2drop")

        // 1) Prefer a prebuilt binary bundled with the app (future-proof packaging path).
        if let bundledBinary = bundledCLIBinaryURL() {
            do {
                try installBinary(from: bundledBinary, to: destination)
                return (true, "CLI installed successfully.")
            } catch {
                return (false, "CLI install failed while copying bundled binary.")
            }
        }

        // 2) Development checkout fallback: run the repo script if available.
        if let repoRoot = findLocalRepoRoot(),
           let scriptURL = repoInstallScriptURL(repoRoot: repoRoot) {
            let success = runInstallScript(at: scriptURL, prefix: installPrefix)
            if success {
                return (true, "CLI installed successfully.")
            }
            return (
                false,
                "CLI installation failed. Try running `scripts/install-cli.sh --prefix ~/.local` from the repo."
            )
        }

        return (
            false,
            "CLI installer unavailable in this build (no bundled CLI and no local repo checkout found)."
        )
    }

    private nonisolated static func userLocalPrefixPath() -> String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .path
    }

    private nonisolated static func bundledCLIBinaryURL() -> URL? {
        let bundle = Bundle.main
        let candidates: [URL?] = [
            bundle.url(forResource: "r2drop", withExtension: nil),
            bundle.resourceURL?.appendingPathComponent("r2drop"),
            bundle.resourceURL?.appendingPathComponent("cli/r2drop")
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }

    private nonisolated static func repoInstallScriptURL(repoRoot: URL) -> URL? {
        let scriptURL = repoRoot.appendingPathComponent("scripts/install-cli.sh")
        return FileManager.default.fileExists(atPath: scriptURL.path) ? scriptURL : nil
    }

    private nonisolated static func findLocalRepoRoot() -> URL? {
        let fm = FileManager.default
        var seedURLs: [URL] = []

        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        seedURLs.append(cwd)

        if let pwd = ProcessInfo.processInfo.environment["PWD"] {
            seedURLs.append(URL(fileURLWithPath: pwd, isDirectory: true))
        }

        seedURLs.append(Bundle.main.bundleURL)
        seedURLs.append(Bundle.main.bundleURL.deletingLastPathComponent())

        for seed in seedURLs {
            var current = seed.standardizedFileURL
            while true {
                let script = current.appendingPathComponent("scripts/install-cli.sh")
                let engine = current.appendingPathComponent("engine/Cargo.toml")
                if fm.fileExists(atPath: script.path), fm.fileExists(atPath: engine.path) {
                    return current
                }
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
        return nil
    }

    private nonisolated static func runInstallScript(at scriptURL: URL, prefix: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        // Use --prefix=<value> because the shell script's --prefix parser expects this form reliably.
        process.arguments = [scriptURL.path, "--prefix=\(prefix)"]
        process.environment = installerEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private nonisolated static func installBinary(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        let destinationDir = destination.deletingLastPathComponent()
        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)

        // rwxr-xr-x
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    private nonisolated static func installerEnvironment() -> [String: String] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let existing = ProcessInfo.processInfo.environment
        let existingPath = existing["PATH"] ?? ""
        let extraPaths = [
            home + "/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]

        let mergedPath = (extraPaths + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")

        var env = existing
        env["HOME"] = home
        env["PATH"] = mergedPath
        return env
    }

}
