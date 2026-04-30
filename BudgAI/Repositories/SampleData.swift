import Foundation

enum SampleData {
    static let categories: [SpendingCategory] = [
        SpendingCategory(id: "cat_housing", name: "Housing", systemImage: "house.fill", colorName: "blue", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_groceries", name: "Groceries", systemImage: "cart.fill", colorName: "sage", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_dining", name: "Dining", systemImage: "fork.knife", colorName: "orange", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_coffee", name: "Coffee", systemImage: "cup.and.saucer.fill", colorName: "coffee", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_transit", name: "Gas / Transit", systemImage: "car.fill", colorName: "teal", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_utilities", name: "Utilities", systemImage: "bolt.fill", colorName: "gold", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_shopping", name: "Shopping", systemImage: "bag.fill", colorName: "rose", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_subscriptions", name: "Subscriptions", systemImage: "repeat.circle.fill", colorName: "plum", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_entertainment", name: "Entertainment", systemImage: "popcorn.fill", colorName: "orange", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_health", name: "Health", systemImage: "cross.case.fill", colorName: "red", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_travel", name: "Travel", systemImage: "airplane", colorName: "blue", isSystem: true, isActive: true),
        SpendingCategory(id: "cat_misc", name: "Miscellaneous", systemImage: "square.grid.2x2.fill", colorName: "slate", isSystem: true, isActive: true)
    ]

    static let monthlyBudget = MonthlyBudget(
        id: "budget_\(Date.currentMonthStart.timeIntervalSince1970)",
        month: .currentMonthStart,
        totalBudget: 0,
        currency: "USD"
    )

    static let categoryBudgets: [CategoryBudget] = []

    static let transactions: [BudgetTransaction] = []

    static let rules: [CategorizationRule] = []
}
