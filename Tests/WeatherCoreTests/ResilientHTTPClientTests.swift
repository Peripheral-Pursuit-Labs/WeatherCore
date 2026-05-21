import Testing
import Foundation
@testable import WeatherCore

/// HTTP double that replays a programmed sequence of outcomes, one per attempt, and
/// counts how many times it was called.
private final class SequencedHTTPClient: HTTPClient, @unchecked Sendable {
    enum Outcome: Sendable {
        case status(Int)
        case error(any Error)
    }

    private let outcomes: [Outcome]
    private let lock = NSLock()
    private var index = 0
    private(set) var callCount = 0

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let outcome: Outcome = {
            lock.lock(); defer { lock.unlock() }
            callCount += 1
            let o = outcomes[min(index, outcomes.count - 1)]
            index += 1
            return o
        }()

        switch outcome {
        case .error(let error):
            throw error
        case .status(let code):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(), response)
        }
    }
}

@Suite("ResilientHTTPClient retries transient failures and trips a circuit breaker")
struct ResilientHTTPClientTests {

    private let url = URL(string: "https://api.example.com/forecast")!
    private let noSleep: @Sendable (TimeInterval) async throws -> Void = { _ in }

    private func makeClient(
        wrapping wrapped: any HTTPClient,
        retry: RetryPolicy = .none,
        breaker: CircuitBreakerPolicy = .disabled,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> ResilientHTTPClient {
        ResilientHTTPClient(wrapping: wrapped, retryPolicy: retry, circuitBreaker: breaker, sleep: sleep, now: now)
    }

    @Test func retriesTransientStatusThenSucceeds() async throws {
        let backend = SequencedHTTPClient([.status(503), .status(503), .status(200)])
        let client = makeClient(wrapping: backend, retry: RetryPolicy(maxRetries: 3, jitter: 0), sleep: noSleep)

        let (_, response) = try await client.data(for: URLRequest(url: url))

        #expect(response.statusCode == 200)
        #expect(backend.callCount == 3)
    }

    @Test func returnsLastResponseWhenRetriesExhausted() async throws {
        let backend = SequencedHTTPClient([.status(500)])
        let client = makeClient(wrapping: backend, retry: RetryPolicy(maxRetries: 2, jitter: 0), sleep: noSleep)

        let (_, response) = try await client.data(for: URLRequest(url: url))

        #expect(response.statusCode == 500)
        #expect(backend.callCount == 3, "1 initial + 2 retries")
    }

    @Test func doesNotRetryNonRetryableStatus() async throws {
        let backend = SequencedHTTPClient([.status(404), .status(200)])
        let client = makeClient(wrapping: backend, retry: RetryPolicy(maxRetries: 3, jitter: 0), sleep: noSleep)

        let (_, response) = try await client.data(for: URLRequest(url: url))

        #expect(response.statusCode == 404)
        #expect(backend.callCount == 1, "4xx is not retried")
    }

    @Test func retriesTransientThrownErrors() async throws {
        let backend = SequencedHTTPClient([.error(URLError(.timedOut)), .status(200)])
        let client = makeClient(wrapping: backend, retry: RetryPolicy(maxRetries: 2, jitter: 0), sleep: noSleep)

        let (_, response) = try await client.data(for: URLRequest(url: url))

        #expect(response.statusCode == 200)
        #expect(backend.callCount == 2)
    }

    @Test func backoffGrowsExponentially() async throws {
        let backend = SequencedHTTPClient([.status(503), .status(503), .status(503), .status(200)])
        let recorded = Recorder()
        let client = makeClient(
            wrapping: backend,
            retry: RetryPolicy(maxRetries: 3, baseDelay: 0.5, multiplier: 2.0, jitter: 0),
            sleep: { await recorded.append($0) }
        )

        _ = try await client.data(for: URLRequest(url: url))

        #expect(await recorded.delays == [0.5, 1.0, 2.0])
    }

    @Test func circuitOpensAfterThresholdAndFailsFast() async throws {
        // Always fails. Breaker trips after 2 consecutive failures.
        let backend = SequencedHTTPClient([.status(500)])
        let client = makeClient(
            wrapping: backend,
            retry: .none,
            breaker: CircuitBreakerPolicy(failureThreshold: 2, resetTimeout: 30),
            sleep: noSleep
        )

        // Two real failures trip the circuit.
        _ = try await client.data(for: URLRequest(url: url))
        _ = try await client.data(for: URLRequest(url: url))
        #expect(backend.callCount == 2)

        // Third call should fail fast without touching the backend.
        await #expect(throws: ProviderError.self) {
            _ = try await client.data(for: URLRequest(url: self.url))
        }
        #expect(backend.callCount == 2, "circuit open → backend not called")
    }

    @Test func circuitHalfOpensAfterResetTimeout() async throws {
        let backend = SequencedHTTPClient([.status(500), .status(500), .status(200)])
        let clock = Clock(start: Date(timeIntervalSince1970: 1_000))
        let client = makeClient(
            wrapping: backend,
            retry: .none,
            breaker: CircuitBreakerPolicy(failureThreshold: 2, resetTimeout: 30),
            sleep: noSleep,
            now: { clock.now }
        )

        _ = try await client.data(for: URLRequest(url: url))   // fail 1
        _ = try await client.data(for: URLRequest(url: url))   // fail 2 → open
        #expect(backend.callCount == 2)

        // Still open before the timeout elapses → fails fast.
        await #expect(throws: ProviderError.self) {
            _ = try await client.data(for: URLRequest(url: self.url))
        }
        #expect(backend.callCount == 2)

        // Advance past the reset timeout → half-open allows a trial that now succeeds.
        clock.advance(by: 31)
        let (_, response) = try await client.data(for: URLRequest(url: url))
        #expect(response.statusCode == 200)
        #expect(backend.callCount == 3)
    }
}

private actor Recorder {
    private(set) var delays: [TimeInterval] = []
    func append(_ delay: TimeInterval) { delays.append(delay) }
}

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(start: Date) { current = start }
    var now: Date { lock.lock(); defer { lock.unlock() }; return current }
    func advance(by seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; current.addTimeInterval(seconds) }
}
