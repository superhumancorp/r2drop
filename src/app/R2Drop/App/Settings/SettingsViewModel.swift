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
    @Published var isRecordingHotkey: Bool = false

    // MARK: - CLI Install (FR-046)

    @Published var cliInstalled: Bool = false
    @Published var cliVersion: String = ""
    @Published var cliInstallStatus: String = ""

    // MARK: - Config Directory (FR-050)

    @Published var configDirPath: String = ""

    // MARK: - Lifecycle

    /// Load preferences from config.toml and detect CLI state.
    func load() {
        let config = (try? ConfigManager.load()) ?? R2Config()
        let prefs = config.preferences

        hideDockIcon = prefs.hideDockIcon
        launchAtLogin = prefs.launchAtLogin
        playSound = prefs.playSound
        concurrentUploads = prefs.concurrentUploads
        chunkSizeMb = prefs.chunkSizeMb
        exclusionPatterns = prefs.exclusionPatterns
        followSymlinks = prefs.followSymlinks
        configDirPath = ConfigManager.configDir().path

        detectCLI()
    }

    // MARK: - Save

    /// Persist all preferences to config.toml.
    func save() {
        do {
            var config = try ConfigManager.load()
            config.preferences.hideDockIcon = hideDockIcon
            config.preferences.launchAtLogin = launchAtLogin
            config.preferences.playSound = playSound
            config.preferences.concurrentUploads = concurrentUploads
            config.preferences.chunkSizeMb = chunkSizeMb
            config.preferences.exclusionPatterns = exclusionPatterns
            config.preferences.followSymlinks = followSymlinks
            try ConfigManager.save(config)
        } catch {
            // Best-effort save
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
        hideDockIcon = hide
        NSApp.setActivationPolicy(hide ? .accessory : .regular)
        save()
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

    /// Check if r2drop CLI is installed at /usr/local/bin/r2drop.
    func detectCLI() {
        let cliPath = "/usr/local/bin/r2drop"
        cliInstalled = FileManager.default.fileExists(atPath: cliPath)
        if cliInstalled {
            cliVersion = getCLIVersion(at: cliPath)
        } else {
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
        cliInstallStatus = "Installing..."

        Task.detached {
            let scriptPath = Bundle.main.bundlePath + "/../../../scripts/install-cli.sh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptPath]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            var success = false
            do {
                try process.run()
                process.waitUntilExit()
                success = process.terminationStatus == 0
            } catch {
                // Process failed to launch
            }

            let statusMessage = success
                ? "CLI installed successfully."
                : "Installation failed. Try running scripts/install-cli.sh manually."

            await MainActor.run { [weak self] in
                self?.cliInstallStatus = statusMessage
                self?.detectCLI()
            }
        }
    }

    // MARK: - Hotkey Recording (FR-047)

    /// Start recording a keyboard shortcut.
    func startRecordingHotkey() {
        isRecordingHotkey = true
        hotkeyDisplay = "Press a key combination..."
    }

    /// Stop recording and save the captured shortcut.
    func stopRecordingHotkey(with event: NSEvent?) {
        isRecordingHotkey = false
        guard let event = event else {
            hotkeyDisplay = ""
            return
        }
        hotkeyDisplay = formatHotkey(event)
        // Hotkey persistence is out of scope for P0 MVP config.
        // The key combo is displayed but actual global hotkey registration
        // requires CGEvent taps or Carbon APIs — deferred to later.
    }

    /// Clear the recorded hotkey.
    func clearHotkey() {
        isRecordingHotkey = false
        hotkeyDisplay = ""
    }

    /// Format an NSEvent into a human-readable hotkey string.
    private func formatHotkey(_ event: NSEvent) -> String {
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.control) { parts.append("^") }
        if flags.contains(.option) { parts.append("\u{2325}") }
        if flags.contains(.shift) { parts.append("\u{21E7}") }
        if flags.contains(.command) { parts.append("\u{2318}") }
        if let chars = event.charactersIgnoringModifiers?.uppercased(), !chars.isEmpty {
            parts.append(chars)
        }
        return parts.joined()
    }
}
