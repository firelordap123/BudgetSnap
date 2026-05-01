import Foundation

struct ParsedImportResponse: Codable {
    var importBatchID: String
    var status: ImportStatus
    var transactions: [ParsedTransactionDTO]
    var warnings: [ImportWarning]
}

struct ParsedTransactionDTO: Codable, Hashable {
    var merchantName: String
    var normalizedMerchantName: String
    var transactionDate: Date?
    var amount: Decimal
    var currency: String
    var suggestedCategoryID: String
    var confidence: Double
    var rawText: String
    var transactionType: TransactionType
    var duplicateRisk: Bool
}

struct ImportWarning: Codable, Hashable, Identifiable {
    let id = UUID().uuidString
    var type: String
    var message: String

    enum CodingKeys: String, CodingKey {
        case type
        case message
    }
}
