// R2Drop/App/Accounts/AccountsTabView.swift
// Accounts tab with Tailscale-style sidebar + detail layout and liquid glass styling.
// Left sidebar lists configured accounts with frosted background.
// Right panel shows editable account details via GlassCard sections.
// Empty state uses GlassEmptyState. "Add Account" at bottom of sidebar (FR-042).
// Notifications banner shown at top when Notifications are not authorized.

import SwiftUI
import R2Core

struct AccountsTabView: View {
    @StateObject private var viewModel = AccountsViewModel()
    @ObservedObject private var permissions = PermissionChecker.shared

    var body: some View {
        VStack(spacing: 0) {
            // Permission banner at top (notifications only)
            if permissions.hasIssues {
                PermissionBannerView(permissions: permissions)
                    .padding(.bottom, 8)
            }
            
            Group {
                if viewModel.accounts.isEmpty {
                    emptyState
                } else {
                    sidebarDetailLayout
                }
            }
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Sidebar + Detail Layout (FR-041)

    private var sidebarDetailLayout: some View {
        HSplitView {
            // Left sidebar: account list + add button with frosted glass
            VStack(spacing: 0) {
                accountList
                Divider()
                addAccountButton
            }
            .frame(minWidth: 150, idealWidth: 170, maxWidth: 200)
            .background(.thinMaterial)

            // Right panel: account detail
            AccountDetailView(viewModel: viewModel)
                .frame(minWidth: 300)
        }
    }

    // MARK: - Account List Sidebar

    private var accountList: some View {
        List(viewModel.accounts, id: \.name, selection: $viewModel.selectedAccountName) { account in
            HStack {
                // Account icon
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.body)
                        .lineLimit(1)
                    if !account.bucket.isEmpty {
                        Text(account.bucket)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .tag(account.name)
            .contentShape(Rectangle())
        }
        // When selection changes via sidebar click, populate detail
        .onChange(of: viewModel.selectedAccountName) { newName in
            if let name = newName {
                viewModel.selectAccount(name)
            }
        }
    }

    // MARK: - Add Account Button (FR-042)

    private var addAccountButton: some View {
        Button(action: { viewModel.addAccount() }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                Text("Add Account")
                    .font(.body)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            GlassEmptyState(
                icon: "person.crop.circle.badge.plus",
                title: "Set up your first account",
                subtitle: "Connect your Cloudflare R2 account to start uploading files."
            )

            Button("Add Account") {
                viewModel.addAccount()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
}

// MARK: - Permission Banner

/// Warning banner shown when Notifications are not enabled.
/// Finder Extension banner removed -- no special permissions needed.
struct PermissionBannerView: View {
    @ObservedObject var permissions: PermissionChecker
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !permissions.notificationsAuthorized {
                HStack(spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notifications not enabled")
                            .font(.body)
                            .fontWeight(.medium)
                        Text("Get alerts when uploads complete")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button("Enable") {
                        permissions.openNotificationSettings()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .cornerRadius(8)
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}
