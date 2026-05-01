import SwiftUI

struct ReviewImportView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if store.pendingTransactions.isEmpty {
                    ContentUnavailableView("Nothing to review", systemImage: "checkmark.seal", description: Text("Imported transactions will appear here before they affect your budget."))
                        .premiumCard()
                } else {
                    reviewHeader

                    ForEach(store.pendingTransactions) { transaction in
                        VStack(spacing: 10) {
                            TransactionCard(transaction: transaction, allowsSelection: true)

                            HStack {
                                Button {
                                    store.reject(transaction)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .buttonStyle(.bordered)
                                .tint(AppTheme.danger)

                                Button {
                                    store.markDuplicate(transaction)
                                } label: {
                                    Label("Duplicate", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)

                                Spacer()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            if !store.pendingTransactions.isEmpty {
                HStack(spacing: 10) {
                    Button("Accept Selected") { store.acceptSelectedPending() }
                        .buttonStyle(.borderedProminent)
                        .disabled(store.selectedPendingTransactionIDs.isEmpty)
                    Button("Accept All") { store.acceptAllPending() }
                        .buttonStyle(.bordered)
                    Button("Reject All", role: .destructive) {
                        store.pendingTransactions.forEach { store.reject($0) }
                    }
                    .buttonStyle(.bordered)
                }
                .font(.subheadline.weight(.semibold))
                .padding()
                .background(.ultraThinMaterial)
            }
        }
        .background(AppTheme.background.ignoresSafeArea())
        .navigationTitle("Review Import")
    }

    private var reviewHeader: some View {
        HStack {
            Text("\(store.pendingTransactions.count) transactions to review")
                .font(.headline)
            Spacer()
            Text("\(store.selectedPendingTransactionIDs.count) selected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .premiumCard()
    }
}
