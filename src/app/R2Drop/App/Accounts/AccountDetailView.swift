// R2Drop/App/Accounts/AccountDetailView.swift
// Right-side detail panel with liquid glass card sections (FR-043, FR-044).
// Replaces Form with ScrollView + GlassCard groups for each field section.
// Shows: account info, bucket picker, default path, custom domain, and actions.

import SwiftUI
import R2Core

struct AccountDetailView: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        if let account = viewModel.selectedAccount {
            ScrollView {
                VStack(spacing: 16) {
                    // Account info card
                    accountInfoCard(account)

                    // Bucket picker card
                    bucketCard

                    // Default path card
                    pathCard

                    // Custom domain card
                    customDomainCard

                    // Save button (only when there are unsaved changes)
                    if viewModel.hasUnsavedChanges {
                        HStack {
                            Spacer()
                            Button("Save Changes") {
                                viewModel.saveChanges()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.regular)
                        }
                    }

                    // Actions card: Update Token, Log Out (FR-044)
                    actionsCard(account)
                }
                .padding(20)
            }
        } else {
            // No account selected
            noSelectionView
        }
    }

    // MARK: - Account Info

    private func accountInfoCard(_ account: ConfigAccount) -> some View {
        GlassCard {
            GlassSectionHeader(title: "Account", systemImage: "person.circle")

            GlassInfoRow(label: "Name", value: account.name, valueColor: .primary)

            if !account.accountId.isEmpty {
                Divider().opacity(0.3)
                GlassInfoRow(
                    label: "Account ID",
                    value: account.accountId,
                    monospaced: true
                )
            }
        }
    }

    // MARK: - Bucket Picker

    private var bucketCard: some View {
        GlassCard {
            GlassSectionHeader(title: "Bucket", systemImage: "externaldrive")

            if viewModel.isLoadingBuckets {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Loading buckets...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            } else {
                Picker("Bucket", selection: $viewModel.editBucket) {
                    ForEach(viewModel.availableBuckets, id: \.self) { bucket in
                        Text(bucket).tag(bucket)
                    }
                }
                .onChange(of: viewModel.editBucket) { _ in
                    viewModel.markEdited()
                }

                if let error = viewModel.bucketError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    // MARK: - Default Path

    private var pathCard: some View {
        GlassCard {
            GlassSectionHeader(title: "Default Path", systemImage: "folder")

            TextField("e.g. uploads/screenshots", text: $viewModel.editPath)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.editPath) { _ in
                    viewModel.markEdited()
                }

            if let error = viewModel.pathError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Custom Domain

    private var customDomainCard: some View {
        GlassCard {
            GlassSectionHeader(title: "Custom Domain", systemImage: "globe")

            TextField("e.g. cdn.example.com", text: $viewModel.editCustomDomain)
                .textFieldStyle(.roundedBorder)
                .onChange(of: viewModel.editCustomDomain) { _ in
                    viewModel.markEdited()
                }

            Text("Used for public URL generation. Leave empty to use default R2 URL.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func actionsCard(_ account: ConfigAccount) -> some View {
        GlassCard {
            GlassSectionHeader(title: "Actions", systemImage: "bolt.circle")

            HStack(spacing: 12) {
                Button("Update Token...") {
                    viewModel.updateToken(accountName: account.name)
                }
                .buttonStyle(.bordered)

                Button("Log Out") {
                    viewModel.logOut(accountName: account.name)
                }
                .foregroundColor(.red)
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    // MARK: - No Selection

    private var noSelectionView: some View {
        GlassEmptyState(
            icon: "person.crop.circle",
            title: "Select an account",
            subtitle: "Choose an account from the sidebar to view its details."
        )
    }
}
