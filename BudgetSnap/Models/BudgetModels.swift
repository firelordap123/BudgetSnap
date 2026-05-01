import Foundation
import SwiftUI

enum TransactionStatus: String, Codable, CaseIterable, Identifiable {
    case pendingReview = "pending_review"
    case accepted
    case rejected
    case duplicate

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pendingReview: "Pending Review"
        case .accepted: "Accepted"
        case .rejected: "Rejected"
        case .duplicate: "Possible Duplicate"
        }
    }
}

enum CategorySource: String, Codable, CaseIterable, Identifiable {
    case aiSuggested = "ai_suggested"
    case userRule = "user_rule"
    case userCorrected = "user_corrected"
    case needsReview = "needs_review"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .aiSuggested: "AI suggested"
        case .userRule: "Matched saved rule"
        case .userCorrected: "User corrected"
        case .needsReview: "Needs review"
        }
    }
}

enum TransactionType: String, Codable, CaseIterable, Identifiable {
    case expense
    case credit
    case refund
    case unknown

    var id: String { rawValue }
}

enum RuleMatchType: String, Codable, CaseIterable, Identifiable {
    case exact
    case contains
    case startsWith

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .exact: "Exact"
        case .contains: "Contains"
        case .startsWith: "Starts With"
        }
    }
}

struct SpendingCategory: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var systemImage: String
    var colorName: String
    var isSystem: Bool
    var isActive: Bool

    var color: Color {
        switch colorName.lowercased() {
        case "coffee": Color(red: 0.48, green: 0.31, blue: 0.22)
        case "sage": Color(red: 0.31, green: 0.52, blue: 0.41)
        case "teal": Color(red: 0.12, green: 0.47, blue: 0.48)
        case "blue": Color(red: 0.20, green: 0.36, blue: 0.64)
        case "orange": Color(red: 0.78, green: 0.40, blue: 0.18)
        case "plum": Color(red: 0.44, green: 0.32, blue: 0.56)
        case "rose": Color(red: 0.72, green: 0.30, blue: 0.40)
        case "gold": Color(red: 0.68, green: 0.49, blue: 0.16)
        case "slate": Color(red: 0.33, green: 0.38, blue: 0.43)
        case "red": Color(red: 0.72, green: 0.20, blue: 0.18)
        default: .accentColor
        }
    }
}

struct BudgetTransaction: Identifiable, Codable, Hashable {
    var id: String
    var merchantName: String
    var normalizedMerchantName: String
    var transactionDate: Date
    var amount: Decimal
    var currency: String
    var categoryID: String
    var status: TransactionStatus
    var categorySource: CategorySource
    var confidence: Double
    var rawText: String
    var duplicateRisk: Bool
    var transactionType: TransactionType
    var createdAt: Date
    var updatedAt: Date
}

struct MonthlyBudget: Identifiable, Codable, Hashable {
    var id: String
    var month: Date
    var totalBudget: Decimal
    var currency: String
}

struct CategoryBudget: Identifiable, Codable, Hashable {
    var id: String
    var month: Date
    var categoryID: String
    var amount: Decimal
}

struct CategorizationRule: Identifiable, Codable, Hashable {
    var id: String
    var matchType: RuleMatchType
    var matchValue: String
    var normalizedMerchantName: String
    var categoryID: String
    var createdFromTransactionID: String?
    var usageCount: Int
    var lastUsedAt: Date?
    var createdAt: Date

    func matches(merchantText: String, normalizedMerchant: String) -> Bool {
        let value = matchValue.normalizedForMatching
        let merchant = merchantText.normalizedForMatching
        let normalized = normalizedMerchant.normalizedForMatching

        switch matchType {
        case .exact:
            return merchant == value || normalized == value
        case .contains:
            return merchant.contains(value) || normalized.contains(value)
        case .startsWith:
            return merchant.hasPrefix(value) || normalized.hasPrefix(value)
        }
    }
}

struct DashboardSummary: Hashable {
    var month: Date
    var totalBudget: Decimal
    var totalSpent: Decimal
    var remaining: Decimal
    var percentUsed: Double
    var categorySummaries: [CategorySpendSummary]
    var recentTransactions: [BudgetTransaction]
    var pendingReviewCount: Int
}

struct CategorySpendSummary: Identifiable, Hashable {
    var id: String { category.id }
    var category: SpendingCategory
    var spent: Decimal
    var budget: Decimal

    var percentUsed: Double {
        guard budget > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / budget).doubleValue
    }
}
