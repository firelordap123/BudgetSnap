import SwiftUI

struct TransactionCard: View {
    @EnvironmentObject private var store: AppStore
    let transaction: BudgetTransaction
    var allowsSelection = false

    @State private var rememberRule = true
    @State private var showEditor = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(transaction.normalizedMerchantName)
                        .font(.headline)
                        .foregroundStyle(AppTheme.ink)
                    Text(Formatters.shortDate.string(from: transaction.transactionDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(Formatters.currencyString(transaction.amount, currencyCode: transaction.currency))
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            HStack(spacing: 10) {
                Menu {
                    ForEach(store.categories) { category in
                        Button {
                            store.updateCategory(transaction: transaction, categoryID: category.id, rememberRule: rememberRule)
                        } label: {
                            Label(category.name, systemImage: category.systemImage)
                        }
                    }
                } label: {
                    CategoryChip(category: store.category(for: transaction.categoryID))
                }

                Spacer()

                Button {
                    showEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .frame(width: 34, height: 34)
                        .background(.primary.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                if allowsSelection {
                    Button {
                        store.toggleSelection(for: transaction.id)
                    } label: {
                        Image(systemName: store.selectedPendingTransactionIDs.contains(transaction.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if transaction.duplicateRisk {
                DuplicateBadge()
            }

            if allowsSelection {
                Toggle("Remember category changes", isOn: $rememberRule)
                    .font(.caption)
                    .toggleStyle(.switch)
            }
        }
        .premiumCard()
        .sheet(isPresented: $showEditor) {
            TransactionEditorView(transaction: transaction)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct DuplicateBadge: View {
    var body: some View {
        Text("Possible duplicate")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppTheme.warning.opacity(0.15), in: Capsule())
            .foregroundStyle(AppTheme.warning)
    }
}
