// R2Drop/App/ConflictResolution/ConflictDialog.swift
// NSAlert-based conflict resolution dialog (FR-065).
// Shows when an upload target already exists in R2 with a different hash.
// Displays existing file info and offers Overwrite / Skip / Rename options
// with an "Apply to all" checkbox for batch operations.

import AppKit
import Foundation

// MARK: - ConflictDialogResult

/// Result from the conflict resolution dialog.
struct ConflictDialogResult {
    let choice: ConflictChoice
    let applyToAll: Bool
}

// MARK: - ConflictDialog

/// Presents an NSAlert for upload conflict resolution.
/// The dialog shows the conflicting file name, existing file's size and
/// last modified date, and the local file's size for comparison.
@MainActor
enum ConflictDialog {

    /// Show the conflict dialog and return the user's choice.
    /// - Parameters:
    ///   - fileName: Name of the file being uploaded.
    ///   - localSize: Size of the local file in bytes.
    ///   - existingInfo: Metadata about the existing R2 object.
    /// - Returns: The user's choice and whether to apply to all.
    static func show(
        fileName: String,
        localSize: UInt64,
        existingInfo: ExistingObjectInfo
    ) -> ConflictDialogResult {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\"\(fileName)\" already exists in R2"

        // Build informative text with size and date comparison
        var details = "Local file: \(formatSize(localSize))"
        if let remoteSize = existingInfo.contentLength {
            details += "\nExisting file: \(formatSize(remoteSize))"
        }
        if let date = existingInfo.lastModified {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            details += "\nLast modified: \(formatter.string(from: date))"
        }
        details += "\n\nWhat would you like to do?"
        alert.informativeText = details

        // Buttons are ordered: Overwrite (first), Skip (second), Rename (third)
        alert.addButton(withTitle: "Overwrite")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Rename")

        // "Apply to all" checkbox for batch conflicts
        let checkbox = NSButton(
            checkboxWithTitle: "Apply to all remaining conflicts",
            target: nil, action: nil
        )
        alert.accessoryView = checkbox

        let response = alert.runModal()
        let applyToAll = checkbox.state == .on

        // Map button response to ConflictChoice
        let choice: ConflictChoice
        switch response {
        case .alertFirstButtonReturn:
            choice = .overwrite
        case .alertSecondButtonReturn:
            choice = .skip
        default:
            // Third button = Rename
            choice = .rename
        }

        return ConflictDialogResult(choice: choice, applyToAll: applyToAll)
    }

    // MARK: - Helpers

    private static func formatSize(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
