import Foundation
import Vision
import UIKit

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

        var texts: [String] = []
        for data in imageData {
            texts.append(try await extractText(from: data))
        }

        let token = try await authTokenProvider()
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/imports/screenshots/process"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        request.httpBody = try JSONEncoder().encode(["texts": texts])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ImportAPIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)

            if let date = Formatters.apiDateOnly.date(from: value) {
                return date
            }

            if let date = Formatters.apiISO8601.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date string: \(value)"
            )
        }
        return try decoder.decode(ParsedImportResponse.self, from: data)
    }

    private func extractText(from imageData: Data) async throws -> String {
        guard let cgImage = UIImage(data: imageData)?.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let text = (request.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n") ?? ""
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            let handler = VNImageRequestHandler(cgImage: cgImage)
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
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
