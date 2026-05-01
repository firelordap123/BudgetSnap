import SwiftUI

struct ImportView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showReview = false
    @State private var showPlaidLink = false
    @State private var linkToken: String?
    @State private var isLoadingToken = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    heroCard

                    if store.linkedAccounts.isEmpty {
                        emptyState
                    } else {
                        accountsList
                    }

                    connectButton

                    if let error = store.syncErrorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppTheme.danger)
                            .premiumCard()
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Import")
            .navigationDestination(isPresented: $showReview) {
                ReviewImportView()
            }
            .fullScreenCover(isPresented: $showPlaidLink) {
                if let token = linkToken {
                    PlaidLinkView(
                        linkToken: token,
                        onSuccess: { publicToken, institutionName, institutionId in
                            showPlaidLink = false
                            Task {
                                await store.exchangePlaidToken(
                                    publicToken: publicToken,
                                    institutionName: institutionName,
                                    institutionId: institutionId
                                )
                            }
                        },
                        onExit: { showPlaidLink = false }
                    )
                }
            }
            .task { await store.loadLinkedAccounts() }
        }
    }

    // MARK: - Subviews

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            Image(systemName: "building.columns")
                .font(.largeTitle)
                .foregroundStyle(AppTheme.accent)
            Text("Sync your bank.")
                .font(.title2.weight(.bold))
            Text("Connect your accounts and pull in this month's transactions with one tap.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .premiumCard(padding: 20)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "link.badge.plus")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No accounts connected yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .premiumCard(padding: 24)
    }

    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Accounts")
                .font(.headline)
                .padding(.horizontal, 4)

            ForEach(store.linkedAccounts) { account in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(account.institutionName)
                            .font(.subheadline.weight(.semibold))
                        Text("Connected \(formattedDate(account.linkedAt))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await store.syncPlaid(itemId: account.itemId)
                            if store.syncErrorMessage == nil {
                                showReview = true
                            }
                        }
                    } label: {
                        if store.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                                .padding(.horizontal, 8)
                        } else {
                            Text("Sync")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(store.isSyncing)
                }
                .premiumCard()
            }
        }
    }

    private var connectButton: some View {
        Button {
            Task {
                isLoadingToken = true
                store.syncErrorMessage = nil
                do {
                    linkToken = try await store.createLinkToken()
                    showPlaidLink = true
                } catch {
                    store.syncErrorMessage = error.localizedDescription
                }
                isLoadingToken = false
            }
        } label: {
            HStack {
                if isLoadingToken { ProgressView().tint(.white) }
                Label(
                    isLoadingToken ? "Connecting..." : "Connect Bank Account",
                    systemImage: "plus.circle"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isLoadingToken || store.isSyncing)
    }

    // MARK: - Helpers

    private func formattedDate(_ isoString: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: isoString) ?? ISO8601DateFormatter().date(from: isoString) {
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .none
            return f.string(from: date)
        }
        return isoString
    }
}
