import Foundation

struct PlaidLinkedAccount: Codable, Identifiable {
    let id: String
    let institutionName: String
    let institutionId: String
    let itemId: String
    let linkedAt: String
}

enum PlaidAPIError: LocalizedError {
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an invalid response."
        case .serverMessage(let message): message
        }
    }
}

protocol PlaidAPIClient {
    func createLinkToken() async throws -> String
    func exchangeToken(publicToken: String, institutionName: String, institutionId: String) async throws
    func fetchLinkedAccounts() async throws -> [PlaidLinkedAccount]
    func syncTransactions(itemId: String?) async throws -> ParsedImportResponse
}

struct URLSessionPlaidAPIClient: PlaidAPIClient {
    let baseURL: URL
    let authTokenProvider: () async throws -> String

    func createLinkToken() async throws -> String {
        let data = try await post(path: "/api/plaid/link-token", body: EmptyBody())
        return try JSONDecoder().decode(LinkTokenResponse.self, from: data).linkToken
    }

    func exchangeToken(publicToken: String, institutionName: String, institutionId: String) async throws {
        _ = try await post(
            path: "/api/plaid/exchange-token",
            body: ExchangeTokenRequest(publicToken: publicToken, institutionName: institutionName, institutionId: institutionId)
        )
    }

    func fetchLinkedAccounts() async throws -> [PlaidLinkedAccount] {
        let data = try await get(path: "/api/plaid/accounts")
        return try JSONDecoder().decode(AccountsResponse.self, from: data).accounts
    }

    func syncTransactions(itemId: String?) async throws -> ParsedImportResponse {
        let data = try await post(path: "/api/plaid/sync", body: SyncRequest(itemId: itemId))
        return try dateDecoder.decode(ParsedImportResponse.self, from: data)
    }

    // MARK: - Internals

    private var dateDecoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = Formatters.apiDateOnly.date(from: value) { return date }
            if let date = Formatters.apiISO8601.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(value)")
        }
        return d
    }

    private func post<B: Encodable>(path: String, body: B) async throws -> Data {
        let token = try await authTokenProvider()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await execute(request)
    }

    private func get(path: String) async throws -> Data {
        let token = try await authTokenProvider()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await execute(request)
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw PlaidAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Status \(http.statusCode)"
            throw PlaidAPIError.serverMessage(message)
        }
        return data
    }
}

private struct EmptyBody: Encodable {}
private struct LinkTokenResponse: Decodable { let linkToken: String }
private struct ExchangeTokenRequest: Encodable {
    let publicToken: String
    let institutionName: String
    let institutionId: String
}
private struct SyncRequest: Encodable { let itemId: String? }
private struct AccountsResponse: Decodable { let accounts: [PlaidLinkedAccount] }
