// R2Drop/App/StatusBarDragView.swift
// Transparent overlay view for accepting file drops on the menu bar status item.
// Added as a subview of NSStatusBarButton. Forwards mouse events to the button
// so clicking still opens the dropdown menu. Drag-and-drop events are handled here.

import AppKit

final class StatusBarDragView: NSView {

    /// Called when the user drops files onto the status bar icon.
    var onFilesDropped: (([URL]) -> Void)?

    // MARK: - Init

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - Mouse Event Forwarding

    // Forward mouse events to the button (superview) so the menu still opens on click.
    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        superview?.rightMouseDown(with: event)
    }

    // MARK: - Drawing

    // Don't draw anything — the button's icon shows through.
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {}

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canRead = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return canRead ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            return false
        }
        onFilesDropped?(urls)
        return true
    }
}
