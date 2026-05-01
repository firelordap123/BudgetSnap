import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    private var repository: any BudgetRepository
    private let ruleEngine = CategorizationRuleEngine()

    @Published var isSyncing = false
    @Published var syncErrorMessage: String?
    @Published var selectedPendingTransactionIDs = Set<String>()
    @Published var didCompleteSetup = false

    init(repository: any BudgetRepository) {
        self.repository = repository
    }

    var allCategories: [SpendingCategory] { repository.categories }
    var categories: [SpendingCategory] { repository.categories.filter(\.isActive) }
    var transactions: [BudgetTransaction] { repository.transactions }
    var rules: [CategorizationRule] { repository.rules }

    var pendingTransactions: [BudgetTransaction] {
        repository.transactions
            .filter { $0.status == .pendingReview || $0.status == .duplicate }
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    var acceptedTransactions: [BudgetTransaction] {
        repository.transactions
            .filter { $0.status == .accepted }
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    var dashboardSummary: DashboardSummary {
        let accepted = acceptedTransactions
        let spent = accepted.reduce(Decimal.zero) { $0 + $1.amount }
        let budget = repository.monthlyBudget.totalBudget
        let remaining = budget - spent
        let percent = budget > 0 ? NSDecimalNumber(decimal: spent / budget).doubleValue : 0

        let categorySummaries = categories.map { category in
            let categorySpent = accepted
                .filter { $0.categoryID == category.id }
                .reduce(Decimal.zero) { $0 + $1.amount }
            let categoryBudget = repository.categoryBudgets.first { $0.categoryID == category.id }?.amount ?? 0
            return CategorySpendSummary(category: category, spent: categorySpent, budget: categoryBudget)
        }
        .sorted { $0.spent > $1.spent }

        return DashboardSummary(
            month: repository.monthlyBudget.month,
            totalBudget: budget,
            totalSpent: spent,
            remaining: remaining,
            percentUsed: percent,
            categorySummaries: categorySummaries,
            recentTransactions: Array(accepted.prefix(5)),
            pendingReviewCount: pendingTransactions.count
        )
    }

    func category(for id: String) -> SpendingCategory? {
        categories.first { $0.id == id }
    }

    func savePendingFromResponse(_ response: ParsedImportResponse) {
        let pending = response.transactions.map { dto in
            let ruled = ruleEngine.applyRules(to: dto, rules: repository.rules)
            return BudgetTransaction(
                id: UUID().uuidString,
                merchantName: ruled.merchantName,
                normalizedMerchantName: ruled.normalizedMerchantName,
                transactionDate: ruled.transactionDate ?? .now,
                amount: ruled.amount,
                currency: ruled.currency,
                categoryID: ruled.suggestedCategoryID,
                status: ruled.duplicateRisk ? .duplicate : .pendingReview,
                categorySource: ruled.suggestedCategoryID == dto.suggestedCategoryID ? .aiSuggested : .userRule,
                confidence: ruled.confidence,
                rawText: ruled.rawText,
                duplicateRisk: ruled.duplicateRisk,
                transactionType: ruled.transactionType,
                createdAt: .now,
                updatedAt: .now
            )
        }
        repository.savePendingTransactions(pending)
        selectedPendingTransactionIDs = Set(pending.map(\.id))
    }

    func toggleSelection(for transactionID: String) {
        if selectedPendingTransactionIDs.contains(transactionID) {
            selectedPendingTransactionIDs.remove(transactionID)
        } else {
            selectedPendingTransactionIDs.insert(transactionID)
        }
    }

    func acceptAllPending() {
        repository.acceptTransactions(ids: Set(pendingTransactions.map(\.id)))
        selectedPendingTransactionIDs.removeAll()
    }

    func acceptSelectedPending() {
        repository.acceptTransactions(ids: selectedPendingTransactionIDs)
        selectedPendingTransactionIDs.removeAll()
    }

    func reject(_ transaction: BudgetTransaction) {
        repository.rejectTransaction(id: transaction.id)
        selectedPendingTransactionIDs.remove(transaction.id)
    }

    func updateTransaction(_ transaction: BudgetTransaction) {
        repository.updateTransaction(transaction)
    }

    func markDuplicate(_ transaction: BudgetTransaction) {
        var updated = transaction
        updated.status = .duplicate
        updated.duplicateRisk = true
        updated.updatedAt = .now
        repository.updateTransaction(updated)
    }

    func updateCategory(transaction: BudgetTransaction, categoryID: String, rememberRule: Bool) {
        var updated = transaction
        updated.categoryID = categoryID
        updated.categorySource = .userCorrected
        updated.updatedAt = .now
        repository.updateTransaction(updated)

        if rememberRule {
            let rule = ruleEngine.createRule(from: updated)
            repository.addRule(rule)
        }
    }

    func updateTotalBudget(_ amount: Decimal) {
        var budget = repository.monthlyBudget
        budget.totalBudget = amount
        repository.updateMonthlyBudget(budget)
    }

    func budgetAmount(for categoryID: String) -> Decimal {
        repository.categoryBudgets.first { $0.categoryID == categoryID }?.amount ?? 0
    }

    func updateCategoryBudget(categoryID: String, amount: Decimal) {
        repository.updateCategoryBudget(categoryID: categoryID, amount: amount)
    }

    func updateRule(_ rule: CategorizationRule) {
        repository.updateRule(rule)
    }

    func deleteRule(_ rule: CategorizationRule) {
        repository.deleteRule(id: rule.id)
    }

    func addCategory(name: String, systemImage: String = "tag.fill", colorName: String = "teal") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        repository.addCategory(
            SpendingCategory(
                id: "cat_\(UUID().uuidString)",
                name: trimmed,
                systemImage: systemImage,
                colorName: colorName,
                isSystem: false,
                isActive: true
            )
        )
    }

    func updateCategory(_ category: SpendingCategory) {
        repository.updateCategory(category)
    }
}
