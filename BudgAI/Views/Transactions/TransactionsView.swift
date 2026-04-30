import SwiftUI

struct TransactionsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var searchText = ""
    @State private var selectedCategoryID: String?
    @State private var selectedStatus: TransactionStatus = .accepted

    private var filteredTransactions: [BudgetTransaction] {
        store.transactions
            .filter { $0.status == selectedStatus }
            .filter { transaction in
                let matchesSearch = searchText.isEmpty || transaction.merchantName.localizedCaseInsensitiveContains(searchText) || transaction.normalizedMerchantName.localizedCaseInsensitiveContains(searchText)
                let matchesCategory = selectedCategoryID == nil || transaction.categoryID == selectedCategoryID
                return matchesSearch && matchesCategory
            }
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    statusPicker
                    categoryFilter

                    if filteredTransactions.isEmpty {
                        ContentUnavailableView("No transactions", systemImage: "list.bullet.rectangle", description: Text("Matching transactions will show here."))
                            .premiumCard()
                    } else {
                        ForEach(filteredTransactions) { transaction in
                            TransactionCard(transaction: transaction)
                        }
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Transactions")
            .searchable(text: $searchText, prompt: "Search merchant")
        }
    }

    private var statusPicker: some View {
        Picker("Status", selection: $selectedStatus) {
            Text("Accepted").tag(TransactionStatus.accepted)
            Text("Review").tag(TransactionStatus.pendingReview)
            Text("Duplicates").tag(TransactionStatus.duplicate)
            Text("Rejected").tag(TransactionStatus.rejected)
        }
        .pickerStyle(.segmented)
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    selectedCategoryID = nil
                } label: {
                    Text("All")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(selectedCategoryID == nil ? AppTheme.accent.opacity(0.16) : .black.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)

                ForEach(store.categories) { category in
                    Button {
                        selectedCategoryID = category.id
                    } label: {
                        CategoryChip(category: category)
                            .opacity(selectedCategoryID == nil || selectedCategoryID == category.id ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
