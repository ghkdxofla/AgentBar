import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidResponse
    case unauthorized
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case timeout
    case noData
    case decodingError(String)
    case networkError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid server response"
        case .unauthorized: "Unauthorized — check your API key"
        case .rateLimited: "Rate limited — try again later"
        case .serverError(let code): "Server error (\(code))"
        case .httpError(let code): "HTTP error (\(code))"
        case .timeout: "Request timed out"
        case .noData: "No data available"
        case .decodingError(let msg): "Decoding error: \(msg)"
        case .networkError(let msg): "Network error: \(msg)"
        }
    }
}
