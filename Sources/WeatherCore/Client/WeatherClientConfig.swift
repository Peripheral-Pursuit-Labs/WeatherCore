import Foundation

public struct WeatherClientConfig: Sendable {
    public let pirateWeatherAPIKey: String?
    public let nwsUserAgent: String?
    /// Enables Apple's native WeatherKit provider. Requires the WeatherKit
    /// entitlement on the host app; no API key is passed here.
    public let enableWeatherKit: Bool
    public let defaultUnits: UnitSystem
    public let cacheTTL: TimeInterval
    public let requestTimeout: TimeInterval
    /// Retry behavior for transient network/HTTP failures. Defaults to `.none`.
    public let retryPolicy: RetryPolicy
    /// Per-host circuit breaker that fails fast for repeatedly-failing providers.
    /// Defaults to `.disabled`.
    public let circuitBreaker: CircuitBreakerPolicy

    public init(
        pirateWeatherAPIKey: String? = nil,
        nwsUserAgent: String? = nil,
        enableWeatherKit: Bool = false,
        defaultUnits: UnitSystem = .imperial,
        cacheTTL: TimeInterval = 300,
        requestTimeout: TimeInterval = 15,
        retryPolicy: RetryPolicy = .none,
        circuitBreaker: CircuitBreakerPolicy = .disabled
    ) {
        self.pirateWeatherAPIKey = pirateWeatherAPIKey
        self.nwsUserAgent = nwsUserAgent
        self.enableWeatherKit = enableWeatherKit
        self.defaultUnits = defaultUnits
        self.cacheTTL = cacheTTL
        self.requestTimeout = requestTimeout
        self.retryPolicy = retryPolicy
        self.circuitBreaker = circuitBreaker
    }
}
