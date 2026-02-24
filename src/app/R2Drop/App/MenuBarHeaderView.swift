// R2Drop/App/MenuBarHeaderView.swift
// Custom header view for the menu bar dropdown — Tailscale-style.
// Shows "R2Drop" title, status text, and an NSSwitch pill toggle.
// Used as the first item in the status bar dropdown menu.

import AppKit

final class MenuBarHeaderView: NSView {

    private let titleLabel = NSTextField(labelWithString: "R2Drop")
    private let statusLabel = NSTextField(labelWithString: "Active")
    private let toggle = NSSwitch()

    /// Called when the user flips the toggle. Passes the new enabled state.
    var onToggle: ((Bool) -> Void)?

    /// Update the toggle and status text to reflect current state.
    var isEnabled: Bool = true {
        didSet {
            toggle.state = isEnabled ? .on : .off
            statusLabel.stringValue = isEnabled ? "Active" : "Paused"
        }
    }

    // MARK: - Init

    init() {
        // Fixed width for menu; height determined by constraints.
        super.init(frame: NSRect(x: 0, y: 0, width: 250, height: 48))
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Layout

    private func setupViews() {
        // Title — bold, matches Tailscale's header style
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        titleLabel.isEditable = false
        titleLabel.isBezeled = false
        titleLabel.drawsBackground = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Status — smaller, secondary color ("Active" / "Paused")
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.isEditable = false
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        // Toggle switch (pill-style, same as Tailscale)
        toggle.target = self
        toggle.action = #selector(toggleChanged)
        toggle.state = .on
        toggle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toggle)

        NSLayoutConstraint.activate([
            // Title: top-left
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),

            // Status: below title
            statusLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            statusLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            statusLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),

            // Toggle: vertically centered, right-aligned
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // MARK: - Action

    @objc private func toggleChanged() {
        let newState = toggle.state == .on
        isEnabled = newState
        onToggle?(newState)
    }
}
