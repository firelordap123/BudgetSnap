import Foundation

protocol ImportAPIClient {
    func uploadAndProcessScreenshots(_ imageData: [Data]) async throws -> ParsedImportResponse
}

enum ImportAPIError: LocalizedError {
    case noImages
    case invalidResponse
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .noImages: "Please select at least one screenshot."
        case .invalidResponse: "The import service returned an invalid response."
        case .serverMessage(let message): message
        }
    }
}

struct URLSessionImportAPIClient: ImportAPIClient {
    let baseURL: URL
    let authTokenProvider: () async throws -> String

    func uploadAndProcessScreenshots(_ imageData: [Data]) async throws -> ParsedImportResponse {
        guard !imageData.isEmpty else { throw ImportAPIError.noImages }

        // Production note:
        // 1. POST multipart images to /api/imports/screenshots.
        // 2. POST /api/imports/{batch_id}/process.
        // 3. Decode strict JSON into ParsedImportResponse.
        // Keep this networking boundary isolated so views never know about HTTP details.

        let token = try await authTokenProvider()
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/imports/screenshots/process"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let base64Images = imageData.map { $0.base64EncodedString() }
        request.httpBody = try JSONEncoder().encode(["images": base64Images])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ParsedImportResponse.self, from: data)
    }
}

struct MockImportAPIClient: ImportAPIClient {
    func uploadAndProcessScreenshots(_ imageData: [Data]) async throws -> ParsedImportResponse {
        guard !imageData.isEmpty else { throw ImportAPIError.noImages }
        try await Task.sleep(for: .seconds(1))

        return ParsedImportResponse(
            importBatchID: UUID().uuidString,
            status: .processed,
            transactions: [],
            warnings: []
        )
    }
}
