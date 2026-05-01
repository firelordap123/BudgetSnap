import Foundation

struct CategorizationRuleEngine {
    func applyRules(to dto: ParsedTransactionDTO, rules: [CategorizationRule]) -> ParsedTransactionDTO {
        guard let rule = rules.first(where: {
            $0.matches(merchantText: dto.merchantName, normalizedMerchant: dto.normalizedMerchantName)
        }) else {
            return dto
        }

        var updated = dto
        updated.suggestedCategoryID = rule.categoryID
        return updated
    }

    func createRule(from transaction: BudgetTransaction, matchType: RuleMatchType = .contains) -> CategorizationRule {
        let matchValue = transaction.normalizedMerchantName.normalizedForMatching

        return CategorizationRule(
            id: UUID().uuidString,
            matchType: matchType,
            matchValue: matchValue,
            normalizedMerchantName: transaction.normalizedMerchantName,
            categoryID: transaction.categoryID,
            createdFromTransactionID: transaction.id,
            usageCount: 0,
            lastUsedAt: nil,
            createdAt: .now
        )
    }
}
