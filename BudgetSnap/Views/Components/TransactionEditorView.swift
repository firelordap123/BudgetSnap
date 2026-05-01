import SwiftUI

struct TransactionEditorView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var transaction: BudgetTransaction
    @State private var amountText: String
    @State private var rememberRule = true

    init(transaction: BudgetTransaction) {
        _transaction = State(initialValue: transaction)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    TextField("Merchant", text: $transaction.normalizedMerchantName)
                    DatePicker("Date", selection: $transaction.transactionDate, displayedComponents: .date)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                Section("Category") {
                    Picker("Category", selection: $transaction.categoryID) {
                        ForEach(store.categories) { category in
                            Label(category.name, systemImage: category.systemImage).tag(category.id)
                        }
                    }
                    Toggle("Remember this merchant", isOn: $rememberRule)
                }

                Section {
                    Button("Mark as Duplicate", role: .destructive) {
                        store.markDuplicate(transaction)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        transaction.amount = Decimal(string: amountText) ?? transaction.amount
                        transaction.updatedAt = .now
                        store.updateTransaction(transaction)
                        if rememberRule {
                            store.updateCategory(transaction: transaction, categoryID: transaction.categoryID, rememberRule: true)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
