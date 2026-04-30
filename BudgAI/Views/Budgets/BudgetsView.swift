import SwiftUI

struct BudgetsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var totalBudgetText = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    totalBudgetEditor

                    Text("Category Budgets")
                        .font(.title3.weight(.bold))
                        .padding(.top, 4)

                    ForEach(store.dashboardSummary.categorySummaries) { summary in
                        CategoryBudgetEditor(summary: summary)
                    }
                }
                .padding()
            }
            .background(AppTheme.background.ignoresSafeArea())
            .navigationTitle("Budgets")
            .onAppear {
                totalBudgetText = NSDecimalNumber(decimal: store.dashboardSummary.totalBudget).stringValue
            }
        }
    }

    private var totalBudgetEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Total Monthly Budget", systemImage: "target")
                .font(.headline)
            HStack {
                TextField("Amount", text: $totalBudgetText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.bold))
                Button("Save") {
                    store.updateTotalBudget(Decimal(string: totalBudgetText) ?? store.dashboardSummary.totalBudget)
                }
                .buttonStyle(.borderedProminent)
            }
            Text("\(Formatters.currencyString(store.dashboardSummary.remaining)) remaining this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .premiumCard()
    }
}

private struct CategoryBudgetEditor: View {
    @EnvironmentObject private var store: AppStore
    let summary: CategorySpendSummary
    @State private var budgetText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(summary.category.name, systemImage: summary.category.systemImage)
                    .font(.headline)
                    .foregroundStyle(summary.category.color)
                Spacer()
                Text("\(Int(summary.percentUsed * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(summary.percentUsed > 1 ? AppTheme.danger : .secondary)
            }

            ProgressView(value: min(summary.percentUsed, 1))
                .tint(summary.percentUsed > 1 ? AppTheme.danger : summary.category.color)

            HStack {
                TextField("Budget", text: $budgetText)
                    .keyboardType(.decimalPad)
                Button("Update") {
                    store.updateCategoryBudget(categoryID: summary.category.id, amount: Decimal(string: budgetText) ?? summary.budget)
                }
                .buttonStyle(.bordered)
            }

            Text("\(Formatters.currencyString(summary.spent)) spent of \(Formatters.currencyString(summary.budget))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .premiumCard()
        .onAppear {
            budgetText = NSDecimalNumber(decimal: summary.budget).stringValue
        }
    }
}
