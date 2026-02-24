// R2Drop/App/Accounts/AccountsTabView.swift
// Accounts tab for the Preferences window (US-018, FR-041 through FR-044).
// Left sidebar lists configured accounts with selection.
// Right panel shows editable account details.
// "Add Account" button at bottom of sidebar (FR-042).
// Empty state: "Set up your first account" card when no accounts exist.

import SwiftUI
import R2Core

struct AccountsTabView: View {
    @StateObject private var viewModel = AccountsViewModel()

    var body: some View {
        Group {
            if viewModel.accounts.isEmpty {
                emptyState
            } else {
                sidebarDetailLayout
            }
        }
        .onAppear { viewModel.load() }
    }

    // MARK: - Sidebar + Detail Layout (FR-041)

    private var sidebarDetailLayout: some View {
        HSplitView {
            // Left sidebar: account list + add button
            VStack(spacing: 0) {
                accountList
                Divider()
                addAccountButton
            }
            .frame(minWidth: 150, idealWidth: 170, maxWidth: 200)

            // Right panel: account detail
            AccountDetailView(viewModel: viewModel)
                .frame(minWidth: 300)
        }
    }

    // MARK: - Account List Sidebar

    private var accountList: some View {
        List(viewModel.accounts, id: \.name, selection: $viewModel.selectedAccountName) { account in
            HStack {
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
            HStack {
                Image(systemName: "plus")
                Text("Add Account")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.secondary)

            Text("Set up your first account")
                .font(.headline)

            Text("Connect your Cloudflare R2 account to start uploading files.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button("Add Account") {
                viewModel.addAccount()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
