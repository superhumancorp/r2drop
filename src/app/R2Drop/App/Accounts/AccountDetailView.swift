// R2Drop/App/Accounts/AccountDetailView.swift
// Right-side detail panel for the Accounts tab (FR-043, FR-044).
// Shows editable fields: display name, bucket dropdown, default path, custom domain.
// Has "Update Token" and "Log Out" action buttons.

import SwiftUI
import R2Core

struct AccountDetailView: View {
    @ObservedObject var viewModel: AccountsViewModel

    var body: some View {
        if let account = viewModel.selectedAccount {
            Form {
                // Account name (display only — the config key)
                Section {
                    LabeledContent("Account Name") {
                        Text(account.name)
                            .foregroundColor(.primary)
                    }
                    if !account.accountId.isEmpty {
                        LabeledContent("Account ID") {
                            Text(account.accountId)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                }

                // Bucket dropdown (fetched from API)
                Section("Bucket") {
                    bucketPicker
                }

                // Default upload path
                Section("Default Path") {
                    TextField("e.g. uploads/screenshots", text: $viewModel.editPath)
                        .onChange(of: viewModel.editPath) { _ in
                            viewModel.markEdited()
                        }
                    if let error = viewModel.pathError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                // Custom domain URL
                Section("Custom Domain") {
                    TextField("e.g. cdn.example.com", text: $viewModel.editCustomDomain)
                        .onChange(of: viewModel.editCustomDomain) { _ in
                            viewModel.markEdited()
                        }
                    Text("Used for public URL generation. Leave empty to use default R2 URL.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Save button (only shown when there are unsaved changes)
                if viewModel.hasUnsavedChanges {
                    Section {
                        HStack {
                            Spacer()
                            Button("Save Changes") {
                                viewModel.saveChanges()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                // Actions section: Update Token, Log Out (FR-044)
                Section {
                    HStack(spacing: 12) {
                        Button("Update Token...") {
                            viewModel.updateToken(accountName: account.name)
                        }

                        Button("Log Out") {
                            viewModel.logOut(accountName: account.name)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.top, 4)
        } else {
            // No account selected
            noSelectionView
        }
    }

    // MARK: - Bucket Picker

    @ViewBuilder
    private var bucketPicker: some View {
        if viewModel.isLoadingBuckets {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Loading buckets...")
                    .font(.caption)
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

    // MARK: - No Selection

    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Select an account")
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
