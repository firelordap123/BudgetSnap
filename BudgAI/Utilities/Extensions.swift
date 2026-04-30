import Foundation

extension String {
    var normalizedForMatching: String {
        uppercased()
            .replacingOccurrences(of: "[^A-Z0-9 ]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Decimal {
    static func / (lhs: Decimal, rhs: Decimal) -> Decimal {
        var left = lhs
        var right = rhs
        var result = Decimal()
        NSDecimalDivide(&result, &left, &right, .plain)
        return result
    }
}

extension Date {
    static var currentMonthStart: Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    }
}

enum Formatters {
    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter
    }()

    static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    static let monthTitle: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static func currencyString(_ amount: Decimal, currencyCode: String = "USD") -> String {
        currency.currencyCode = currencyCode
        return currency.string(from: NSDecimalNumber(decimal: amount)) ?? "$0.00"
    }
}
