import Foundation
import Combine

@MainActor
final class AppStore: ObservableObject {
    private var repository: any BudgetRepository
    private let plaidClient: any PlaidAPIClient
    private let ruleEngine = CategorizationRuleEngine()

    @Published var isSyncing = false
    @Published var syncErrorMessage: String?
    @Published var linkedAccounts: [PlaidLinkedAccount] = []
    @Published var selectedPendingTransactionIDs = Set<String>()

    // Persisted across launches via UserDefaults
    var didCompleteSetup: Bool {
        get { UserDefaults.standard.bool(forKey: "didCompleteSetup") }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: "didCompleteSetup")
        }
    }

    init(repository: any BudgetRepository, plaidClient: any PlaidAPIClient) {
        self.repository = repository
        self.plaidClient = plaidClient
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
        objectWillChange.send()
        repository.savePendingTransactions(pending)
        selectedPendingTransactionIDs = Set(pending.map(\.id))
    }

    func createLinkToken() async throws -> String {
        try await plaidClient.createLinkToken()
    }

    func exchangePlaidToken(publicToken: String, institutionName: String, institutionId: String) async {
        do {
            try await plaidClient.exchangeToken(publicToken: publicToken, institutionName: institutionName, institutionId: institutionId)
            await loadLinkedAccounts()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    func loadLinkedAccounts() async {
        do {
            linkedAccounts = try await plaidClient.fetchLinkedAccounts()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    func syncPlaid(itemId: String? = nil) async {
        isSyncing = true
        syncErrorMessage = nil
        do {
            let response = try await plaidClient.syncTransactions(itemId: itemId)
            savePendingFromResponse(response)
        } catch {
            syncErrorMessage = error.localizedDescription
        }
        isSyncing = false
    }

    func toggleSelection(for transactionID: String) {
        if selectedPendingTransactionIDs.contains(transactionID) {
            selectedPendingTransactionIDs.remove(transactionID)
        } else {
            selectedPendingTransactionIDs.insert(transactionID)
        }
    }

    func acceptAllPending() {
        objectWillChange.send()
        repository.acceptTransactions(ids: Set(pendingTransactions.map(\.id)))
        selectedPendingTransactionIDs.removeAll()
    }

    func acceptSelectedPending() {
        objectWillChange.send()
        repository.acceptTransactions(ids: selectedPendingTransactionIDs)
        selectedPendingTransactionIDs.removeAll()
    }

    func reject(_ transaction: BudgetTransaction) {
        objectWillChange.send()
        repository.rejectTransaction(id: transaction.id)
        selectedPendingTransactionIDs.remove(transaction.id)
    }

    func updateTransaction(_ transaction: BudgetTransaction) {
        objectWillChange.send()
        repository.updateTransaction(transaction)
    }

    func markDuplicate(_ transaction: BudgetTransaction) {
        var updated = transaction
        updated.status = .duplicate
        updated.duplicateRisk = true
        updated.updatedAt = .now
        objectWillChange.send()
        repository.updateTransaction(updated)
    }

    func updateCategory(transaction: BudgetTransaction, categoryID: String, rememberRule: Bool) {
        var updated = transaction
        updated.categoryID = categoryID
        updated.categorySource = .userCorrected
        updated.updatedAt = .now
        objectWillChange.send()
        repository.updateTransaction(updated)
        if rememberRule {
            repository.addRule(ruleEngine.createRule(from: updated))
        }
    }

    func updateTotalBudget(_ amount: Decimal) {
        var budget = repository.monthlyBudget
        budget.totalBudget = amount
        objectWillChange.send()
        repository.updateMonthlyBudget(budget)
    }

    func budgetAmount(for categoryID: String) -> Decimal {
        repository.categoryBudgets.first { $0.categoryID == categoryID }?.amount ?? 0
    }

    func updateCategoryBudget(categoryID: String, amount: Decimal) {
        objectWillChange.send()
        repository.updateCategoryBudget(categoryID: categoryID, amount: amount)
    }

    func updateRule(_ rule: CategorizationRule) {
        objectWillChange.send()
        repository.updateRule(rule)
    }

    func deleteRule(_ rule: CategorizationRule) {
        objectWillChange.send()
        repository.deleteRule(id: rule.id)
    }

    func addCategory(name: String, systemImage: String = "tag.fill", colorName: String = "teal") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        objectWillChange.send()
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
        objectWillChange.send()
        repository.updateCategory(category)
    }
}
