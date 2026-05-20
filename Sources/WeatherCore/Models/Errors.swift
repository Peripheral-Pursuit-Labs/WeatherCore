import Foundation

public enum ProviderError: Error, Sendable, Codable {
    case missingAPIKey(ProviderID)
    case invalidURL
    case http(status: Int, body: String?)
    case decoding(message: String)
    case rateLimited(retryAfter: TimeInterval?)
    case timeout
    case offline
    case unsupportedHorizon(horizon: String, provider: ProviderID)
    case noData
    case underlying(message: String)
}

extension ProviderError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingAPIKey(let p): "Missing API key for \(p.rawValue)"
        case .invalidURL: "Invalid URL"
        case .http(let status, let body): "HTTP \(status): \(body ?? "")"
        case .decoding(let m): "Decode error: \(m)"
        case .rateLimited(let r): "Rate limited (retry after \(r ?? 0)s)"
        case .timeout: "Request timed out"
        case .offline: "Offline"
        case .unsupportedHorizon(let h, let p): "\(p.rawValue) doesn't support horizon \(h)"
        case .noData: "No data returned"
        case .underlying(let m): "Underlying: \(m)"
        }
    }
}
