// R2Drop/App/ConflictResolution/ConflictResolution.swift
// Conflict resolution model and session-scoped manager (FR-065).
// When an upload target already exists in R2, the user can choose to
// overwrite, skip, or rename. The "Apply to all" choice persists
// for the current session only (resets on app restart).

import Foundation

// MARK: - ConflictChoice

/// User's choice when an upload conflicts with an existing R2 object.
enum ConflictChoice {
    /// Replace the existing object with the new upload.
    case overwrite
    /// Skip this file entirely — do not upload.
    case skip
    /// Upload with a renamed key (appends -<timestamp> suffix).
    case rename
}

// MARK: - ExistingObjectInfo

/// Metadata about the existing R2 object, shown in the conflict dialog.
struct ExistingObjectInfo {
    /// Object size in bytes (nil if unknown).
    let contentLength: UInt64?
    /// Last modification date (nil if unknown).
    let lastModified: Date?
}

// MARK: - ConflictManager

/// Session-scoped conflict resolution manager.
/// Tracks the user's "Apply to all" preference so subsequent conflicts
/// in the same session are resolved automatically without a dialog.
/// Resets on app restart (per acceptance criteria).
@MainActor
final class ConflictManager {
    static let shared = ConflictManager()

    /// The "Apply to all" choice. Nil means ask the user each time.
    private(set) var applyToAllChoice: ConflictChoice?

    private init() {}

    /// Record the user's choice. If applyToAll is true, future conflicts
    /// resolve automatically with this choice.
    func recordChoice(_ choice: ConflictChoice, applyToAll: Bool) {
        if applyToAll {
            applyToAllChoice = choice
        }
    }

    /// Check if we have a stored "Apply to all" decision.
    /// Returns the stored choice, or nil if the user should be prompted.
    func storedChoice() -> ConflictChoice? {
        return applyToAllChoice
    }

    /// Reset the session preference (e.g., for testing).
    func reset() {
        applyToAllChoice = nil
    }

    /// Generate a renamed R2 key by appending a timestamp suffix.
    /// Example: "photos/image.png" → "photos/image-1708790400.png"
    static func renamedKey(_ originalKey: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let url = URL(fileURLWithPath: originalKey)
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().path

        if ext.isEmpty {
            return "\(stem)-\(timestamp)"
        }
        return "\(stem)-\(timestamp).\(ext)"
    }
}
