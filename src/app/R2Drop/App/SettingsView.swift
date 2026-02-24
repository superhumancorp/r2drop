// R2Drop/App/SettingsView.swift
// Preferences window with tab navigation.
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

    var body: some View {
        TabView(selection: $selectedTab) {
            QueueTabView()
                .tabItem { Label("Queue", systemImage: "list.bullet") }
                .tag(SettingsTab.queue)

            AccountsTabView()
                .tabItem { Label("Accounts", systemImage: "person.2") }
                .tag(SettingsTab.accounts)

            SettingsTabView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(SettingsTab.settings)

            HistoryTabView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(SettingsTab.history)

            AboutTabView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
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
