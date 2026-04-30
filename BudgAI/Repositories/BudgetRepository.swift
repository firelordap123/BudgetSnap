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
