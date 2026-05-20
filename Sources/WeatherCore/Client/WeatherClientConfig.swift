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

    public init(
        pirateWeatherAPIKey: String? = nil,
        nwsUserAgent: String? = nil,
        enableWeatherKit: Bool = false,
        defaultUnits: UnitSystem = .imperial,
        cacheTTL: TimeInterval = 300,
        requestTimeout: TimeInterval = 15
    ) {
        self.pirateWeatherAPIKey = pirateWeatherAPIKey
        self.nwsUserAgent = nwsUserAgent
        self.enableWeatherKit = enableWeatherKit
        self.defaultUnits = defaultUnits
        self.cacheTTL = cacheTTL
        self.requestTimeout = requestTimeout
    }
}
