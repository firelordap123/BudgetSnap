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
                totalBudgetText = formatDecimal(store.dashboardSummary.totalBudget)
            }
            .onChange(of: store.dashboardSummary.totalBudget) { _, newValue in
                totalBudgetText = formatDecimal(newValue)
            }
        }
    }

    private var totalBudgetEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Total Monthly Budget", systemImage: "target")
                .font(.headline)
            HStack {
                Text("$").foregroundStyle(.secondary)
                TextField("0.00", text: $totalBudgetText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.bold))
                Button("Save") {
                    if let amount = parseDecimal(totalBudgetText) {
                        store.updateTotalBudget(amount)
                    }
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
                Text("$").foregroundStyle(.secondary)
                TextField("0.00", text: $budgetText)
                    .keyboardType(.decimalPad)
                Button("Update") {
                    if let amount = parseDecimal(budgetText) {
                        store.updateCategoryBudget(categoryID: summary.category.id, amount: amount)
                    }
                }
                .buttonStyle(.bordered)
            }

            Text("\(Formatters.currencyString(summary.spent)) spent of \(Formatters.currencyString(summary.budget))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .premiumCard()
        .onAppear {
            budgetText = formatDecimal(summary.budget)
        }
        .onChange(of: summary.budget) { _, newValue in
            budgetText = formatDecimal(newValue)
        }
    }
}

private func formatDecimal(_ value: Decimal) -> String {
    String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
}

private func parseDecimal(_ text: String) -> Decimal? {
    Decimal(string: text, locale: Locale(identifier: "en_US"))
}
