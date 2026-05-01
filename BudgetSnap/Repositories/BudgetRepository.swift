import Foundation

protocol BudgetRepository {
    var categories: [SpendingCategory] { get set }
    var transactions: [BudgetTransaction] { get set }
    var monthlyBudget: MonthlyBudget { get set }
    var categoryBudgets: [CategoryBudget] { get set }
    var rules: [CategorizationRule] { get set }

    mutating func savePendingTransactions(_ transactions: [BudgetTransaction])
    mutating func acceptTransactions(ids: Set<String>)
    mutating func rejectTransaction(id: String)
    mutating func updateTransaction(_ transaction: BudgetTransaction)
    mutating func addRule(_ rule: CategorizationRule)
    mutating func updateRule(_ rule: CategorizationRule)
    mutating func deleteRule(id: String)
    mutating func updateMonthlyBudget(_ budget: MonthlyBudget)
    mutating func updateCategoryBudget(categoryID: String, amount: Decimal)
    mutating func updateCategory(_ category: SpendingCategory)
    mutating func addCategory(_ category: SpendingCategory)
}

struct JSONFileBudgetRepository: BudgetRepository {
    var categories: [SpendingCategory]
    var transactions: [BudgetTransaction]
    var monthlyBudget: MonthlyBudget
    var categoryBudgets: [CategoryBudget]
    var rules: [CategorizationRule]

    private static let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("budget_data.json")
    }()

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let saved = try? JSONDecoder().decode(PersistedData.self, from: data) {
            categories = saved.categories
            transactions = saved.transactions
            monthlyBudget = saved.monthlyBudget
            categoryBudgets = saved.categoryBudgets
            rules = saved.rules
        } else {
            categories = SampleData.categories
            transactions = SampleData.transactions
            monthlyBudget = SampleData.monthlyBudget
            categoryBudgets = SampleData.categoryBudgets
            rules = SampleData.rules
        }
    }

    private mutating func save() {
        let data = PersistedData(
            categories: categories,
            transactions: transactions,
            monthlyBudget: monthlyBudget,
            categoryBudgets: categoryBudgets,
            rules: rules
        )
        try? JSONEncoder().encode(data).write(to: Self.fileURL)
    }

    mutating func savePendingTransactions(_ transactions: [BudgetTransaction]) {
        self.transactions.append(contentsOf: transactions)
        save()
    }

    mutating func acceptTransactions(ids: Set<String>) {
        transactions = transactions.map { txn in
            guard ids.contains(txn.id) else { return txn }
            var updated = txn; updated.status = .accepted; updated.updatedAt = .now
            return updated
        }
        save()
    }

    mutating func rejectTransaction(id: String) {
        transactions = transactions.map { txn in
            guard txn.id == id else { return txn }
            var updated = txn; updated.status = .rejected; updated.updatedAt = .now
            return updated
        }
        save()
    }

    mutating func updateTransaction(_ transaction: BudgetTransaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
        save()
    }

    mutating func addRule(_ rule: CategorizationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        save()
    }

    mutating func updateRule(_ rule: CategorizationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
        save()
    }

    mutating func deleteRule(id: String) {
        rules.removeAll { $0.id == id }
        save()
    }

    mutating func updateMonthlyBudget(_ budget: MonthlyBudget) {
        monthlyBudget = budget
        save()
    }

    mutating func updateCategoryBudget(categoryID: String, amount: Decimal) {
        if let index = categoryBudgets.firstIndex(where: { $0.categoryID == categoryID }) {
            categoryBudgets[index].amount = amount
        } else {
            categoryBudgets.append(CategoryBudget(id: UUID().uuidString, month: monthlyBudget.month, categoryID: categoryID, amount: amount))
        }
        save()
    }

    mutating func updateCategory(_ category: SpendingCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
        save()
    }

    mutating func addCategory(_ category: SpendingCategory) {
        categories.append(category)
        save()
    }

    private struct PersistedData: Codable {
        var categories: [SpendingCategory]
        var transactions: [BudgetTransaction]
        var monthlyBudget: MonthlyBudget
        var categoryBudgets: [CategoryBudget]
        var rules: [CategorizationRule]
    }
}

struct InMemoryBudgetRepository: BudgetRepository {
    var categories: [SpendingCategory] = SampleData.categories
    var transactions: [BudgetTransaction] = SampleData.transactions
    var monthlyBudget: MonthlyBudget = SampleData.monthlyBudget
    var categoryBudgets: [CategoryBudget] = SampleData.categoryBudgets
    var rules: [CategorizationRule] = SampleData.rules

    mutating func savePendingTransactions(_ transactions: [BudgetTransaction]) {
        self.transactions.append(contentsOf: transactions)
    }

    mutating func acceptTransactions(ids: Set<String>) {
        transactions = transactions.map { txn in
            guard ids.contains(txn.id) else { return txn }
            var updated = txn
            updated.status = .accepted
            updated.updatedAt = .now
            return updated
        }
    }

    mutating func rejectTransaction(id: String) {
        transactions = transactions.map { txn in
            guard txn.id == id else { return txn }
            var updated = txn
            updated.status = .rejected
            updated.updatedAt = .now
            return updated
        }
    }

    mutating func updateTransaction(_ transaction: BudgetTransaction) {
        guard let index = transactions.firstIndex(where: { $0.id == transaction.id }) else { return }
        transactions[index] = transaction
    }

    mutating func addRule(_ rule: CategorizationRule) {
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
    }

    mutating func updateRule(_ rule: CategorizationRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
    }

    mutating func deleteRule(id: String) {
        rules.removeAll { $0.id == id }
    }

    mutating func updateMonthlyBudget(_ budget: MonthlyBudget) {
        monthlyBudget = budget
    }

    mutating func updateCategoryBudget(categoryID: String, amount: Decimal) {
        if let index = categoryBudgets.firstIndex(where: { $0.categoryID == categoryID }) {
            categoryBudgets[index].amount = amount
        } else {
            categoryBudgets.append(CategoryBudget(id: UUID().uuidString, month: monthlyBudget.month, categoryID: categoryID, amount: amount))
        }
    }

    mutating func updateCategory(_ category: SpendingCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else { return }
        categories[index] = category
    }

    mutating func addCategory(_ category: SpendingCategory) {
        categories.append(category)
    }
}
