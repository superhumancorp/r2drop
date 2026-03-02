// R2Drop/App/SettingsView.swift
// Preferences window with icon-based tab bar (like native macOS Preferences).
// Uses a custom toolbar-style tab bar with icons at the top.
// Defaults to Queue tab when uploads are active, otherwise Accounts tab.
// SelectedTabStore allows deep links to switch tabs programmatically (US-022).

import SwiftUI
import R2Core

/// Tab identifiers for the preferences window.
enum SettingsTab: Hashable {
    case queue, accounts, settings, history, about
}

/// Shared store so deep links can programmatically switch tabs.
/// Deep links set `requestedTab`; SettingsView observes it on appear.
@MainActor
final class SelectedTabStore: ObservableObject {
    static let shared = SelectedTabStore()
    /// Set by DeepLinkHandler, consumed by SettingsView on appear.
    @Published var requestedTab: SettingsTab?
    private init() {}
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .accounts
    @ObservedObject private var tabStore = SelectedTabStore.shared

    /// Tab definitions — icon, label, and identifier.
    private let tabs: [(tab: SettingsTab, icon: String, label: String)] = [
        (.queue, "arrow.up.circle", "Uploads"),
        (.accounts, "person.2", "Accounts"),
        (.settings, "gearshape", "Settings"),
        (.history, "clock", "History"),
        (.about, "info.circle", "About"),
    ]

    var body: some View {
        ZStack {
            // Liquid glass background layer
            GlassBackground()

            VStack(spacing: 0) {
                // Custom icon-based tab bar (like native macOS Preferences)
                iconTabBar

                Divider()

                // Tab content
                tabContent
            }
        }
        .frame(width: 600, height: 520)
        .onAppear { selectDefaultTab() }
        // When a deep link requests a specific tab, switch to it.
        .onChange(of: tabStore.requestedTab) { newTab in
            if let tab = newTab {
                selectedTab = tab
                tabStore.requestedTab = nil
            }
        }
    }

    // MARK: - Icon Tab Bar

    /// Custom toolbar-style tab bar with icons and labels, matching
    /// the native macOS System Preferences icon toolbar look.
    private var iconTabBar: some View {
        HStack(spacing: 2) {
            ForEach(tabs, id: \.tab) { item in
                tabButton(item.tab, icon: item.icon, label: item.label)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    /// A single tab button — icon on top, label below.
    /// Selected state uses accent color tint background.
    private func tabButton(_ tab: SettingsTab, icon: String, label: String) -> some View {
        let isSelected = selectedTab == tab

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = tab
            }
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .frame(width: 24, height: 24)
                Text(label)
                    .font(.system(size: 11))
            }
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tab Content

    /// Switches between tab views based on current selection.
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .queue:
            QueueTabView()
        case .accounts:
            AccountsTabView()
        case .settings:
            SettingsTabView()
        case .history:
            HistoryTabView()
        case .about:
            AboutTabView()
        }
    }

    // MARK: - Default Tab Selection

    /// Default to Queue tab when uploads are active, otherwise Accounts tab.
    /// If a deep link requested a specific tab, use that instead.
    private func selectDefaultTab() {
        if let requested = tabStore.requestedTab {
            selectedTab = requested
            tabStore.requestedTab = nil
            return
        }
        let hasUploads: Bool = {
            guard let qm = try? QueueManager() else { return false }
            let uploading = (try? qm.listJobs(status: .uploading)) ?? []
            let pending = (try? qm.listJobs(status: .pending)) ?? []
            return !uploading.isEmpty || !pending.isEmpty
        }()
        selectedTab = hasUploads ? .queue : .accounts
    }
}
