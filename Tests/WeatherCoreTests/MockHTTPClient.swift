import Foundation
@testable import WeatherCore

/// Test double for HTTPClient. Returns canned responses by URL substring match.
public final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    public struct Stub: Sendable {
        public let data: Data
        public let statusCode: Int
        public init(data: Data, statusCode: Int = 200) {
            self.data = data
            self.statusCode = statusCode
        }
    }

    private let lock = NSLock()
    private var stubs: [(matcher: @Sendable (URLRequest) -> Bool, stub: Stub)] = []
    private var _requests: [URLRequest] = []

    public init() {}

    public var requests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return _requests
    }

    public func stub(when matcher: @escaping @Sendable (URLRequest) -> Bool, with stub: Stub) {
        lock.lock(); defer { lock.unlock() }
        stubs.append((matcher, stub))
    }

    public func stubURLContaining(_ substring: String, with stub: Stub) {
        self.stub(when: { request in
            request.url?.absoluteString.contains(substring) ?? false
        }, with: stub)
    }

    private func record(_ request: URLRequest) -> Stub? {
        lock.lock(); defer { lock.unlock() }
        _requests.append(request)
        return stubs.first(where: { $0.matcher(request) })?.stub
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let match = record(request)

        guard let stub = match else {
            throw ProviderError.underlying(message: "No stub for \(request.url?.absoluteString ?? "nil")")
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (stub.data, response)
    }
}
