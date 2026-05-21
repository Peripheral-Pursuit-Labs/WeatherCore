import Foundation
import OSLog

/// Retry-with-exponential-backoff configuration. `.none` disables retries entirely.
public struct RetryPolicy: Sendable {
    /// Retries *after* the first attempt (so total attempts == maxRetries + 1).
    public let maxRetries: Int
    /// Delay before the first retry; subsequent retries grow by `multiplier`.
    public let baseDelay: TimeInterval
    public let multiplier: Double
    /// Upper bound on any single backoff delay.
    public let maxDelay: TimeInterval
    /// Randomization applied to each delay, as a fraction (0...1) of the delay.
    public let jitter: Double

    public init(
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 0.5,
        multiplier: Double = 2.0,
        maxDelay: TimeInterval = 8.0,
        jitter: Double = 0.2
    ) {
        self.maxRetries = max(0, maxRetries)
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
        self.jitter = min(max(0, jitter), 1)
    }

    /// Sensible defaults: up to 2 retries, 0.5s base, doubling, ±20% jitter.
    public static let `default` = RetryPolicy()
    /// No retries — a single attempt.
    public static let none = RetryPolicy(maxRetries: 0)
}

/// Per-host circuit breaker configuration. `.disabled` never opens the circuit.
public struct CircuitBreakerPolicy: Sendable {
    /// Consecutive failures that trip the circuit open for a host.
    public let failureThreshold: Int
    /// How long the circuit stays open before allowing a trial request (half-open).
    public let resetTimeout: TimeInterval

    public init(failureThreshold: Int = 5, resetTimeout: TimeInterval = 30) {
        self.failureThreshold = failureThreshold
        self.resetTimeout = resetTimeout
    }

    var isEnabled: Bool { failureThreshold != Int.max }

    public static let `default` = CircuitBreakerPolicy()
    /// Never trips — every request is allowed through.
    public static let disabled = CircuitBreakerPolicy(failureThreshold: .max, resetTimeout: 0)
}

/// Tracks per-host failure state and decides whether requests may proceed.
/// An actor so the state is safe under the concurrent provider fan-out.
actor CircuitBreaker {
    private enum State {
        case closed(failures: Int)
        case open(until: Date)
        case halfOpen
    }

    private let policy: CircuitBreakerPolicy
    private var states: [String: State] = [:]

    init(policy: CircuitBreakerPolicy) {
        self.policy = policy
    }

    /// Whether a request to `host` may proceed now. Transitions an expired open
    /// circuit to half-open (a single trial).
    func allowRequest(host: String, now: Date) -> Bool {
        guard policy.isEnabled else { return true }
        switch states[host] ?? .closed(failures: 0) {
        case .closed, .halfOpen:
            return true
        case .open(let until):
            if now >= until {
                states[host] = .halfOpen
                return true
            }
            return false
        }
    }

    func recordSuccess(host: String) {
        guard policy.isEnabled else { return }
        states[host] = .closed(failures: 0)
    }

    func recordFailure(host: String, now: Date) {
        guard policy.isEnabled else { return }
        switch states[host] ?? .closed(failures: 0) {
        case .halfOpen, .open:
            // A failed trial (or a failure while open) re-opens the circuit.
            states[host] = .open(until: now.addingTimeInterval(policy.resetTimeout))
        case .closed(let failures):
            let next = failures + 1
            if next >= policy.failureThreshold {
                states[host] = .open(until: now.addingTimeInterval(policy.resetTimeout))
            } else {
                states[host] = .closed(failures: next)
            }
        }
    }
}

/// Decorates any `HTTPClient` with retry-with-exponential-backoff and a per-host circuit
/// breaker. Transient failures (network errors, HTTP 408/429/5xx) are retried; once a host
/// trips the breaker, requests to it fail fast until the reset timeout elapses.
public struct ResilientHTTPClient: HTTPClient {
    private let wrapped: any HTTPClient
    private let retryPolicy: RetryPolicy
    private let breaker: CircuitBreaker
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        wrapping wrapped: any HTTPClient,
        retryPolicy: RetryPolicy = .default,
        circuitBreaker: CircuitBreakerPolicy = .default
    ) {
        self.init(
            wrapping: wrapped,
            retryPolicy: retryPolicy,
            circuitBreaker: circuitBreaker,
            sleep: { seconds in try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)) },
            now: { Date() }
        )
    }

    /// Test seam: inject a no-op sleep and a controllable clock.
    init(
        wrapping wrapped: any HTTPClient,
        retryPolicy: RetryPolicy,
        circuitBreaker: CircuitBreakerPolicy,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void,
        now: @escaping @Sendable () -> Date
    ) {
        self.wrapped = wrapped
        self.retryPolicy = retryPolicy
        self.breaker = CircuitBreaker(policy: circuitBreaker)
        self.sleep = sleep
        self.now = now
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = request.url?.host ?? "unknown"
        let log = WeatherLog.networking

        guard await breaker.allowRequest(host: host, now: now()) else {
            log.debug("Circuit open for \(host, privacy: .public); failing fast")
            throw ProviderError.offline
        }

        let maxAttempts = retryPolicy.maxRetries + 1
        var attempt = 1

        while true {
            do {
                let (data, response) = try await wrapped.data(for: request)

                if (200..<300).contains(response.statusCode) {
                    await breaker.recordSuccess(host: host)
                    return (data, response)
                }

                if Self.isRetryableStatus(response.statusCode), attempt < maxAttempts {
                    log.debug("Retrying \(host, privacy: .public) after HTTP \(response.statusCode) (attempt \(attempt)/\(maxAttempts - 1))")
                    try await sleep(backoffDelay(forAttempt: attempt))
                    attempt += 1
                    continue
                }

                // Non-retryable status, or retries exhausted: surface it to the provider.
                await breaker.recordFailure(host: host, now: now())
                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Self.isRetryableError(error), attempt < maxAttempts {
                    log.debug("Retrying \(host, privacy: .public) after error \(error.localizedDescription, privacy: .public) (attempt \(attempt)/\(maxAttempts - 1))")
                    try await sleep(backoffDelay(forAttempt: attempt))
                    attempt += 1
                    continue
                }
                await breaker.recordFailure(host: host, now: now())
                throw error
            }
        }
    }

    // MARK: - Helpers

    /// Exponential backoff with optional jitter. `attempt` is 1-based; the first retry
    /// (attempt 1) waits `baseDelay`.
    private func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        let raw = min(retryPolicy.baseDelay * pow(retryPolicy.multiplier, Double(attempt - 1)), retryPolicy.maxDelay)
        guard retryPolicy.jitter > 0 else { return raw }
        let delta = raw * retryPolicy.jitter
        return max(0, raw + Double.random(in: -delta...delta))
    }

    static func isRetryableStatus(_ status: Int) -> Bool {
        switch status {
        case 408, 429, 500, 502, 503, 504: true
        default: false
        }
    }

    static func isRetryableError(_ error: any Error) -> Bool {
        if let providerError = error as? ProviderError {
            switch providerError {
            case .timeout, .offline, .rateLimited: return true
            default: return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }
}
