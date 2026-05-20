import Foundation

public struct WeatherClientConfig: Sendable {
    public let pirateWeatherAPIKey: String?
    public let nwsUserAgent: String?
    public let defaultUnits: UnitSystem
    public let cacheTTL: TimeInterval
    public let requestTimeout: TimeInterval

    public init(
        pirateWeatherAPIKey: String? = nil,
        nwsUserAgent: String? = nil,
        defaultUnits: UnitSystem = .imperial,
        cacheTTL: TimeInterval = 300,
        requestTimeout: TimeInterval = 15
    ) {
        self.pirateWeatherAPIKey = pirateWeatherAPIKey
        self.nwsUserAgent = nwsUserAgent
        self.defaultUnits = defaultUnits
        self.cacheTTL = cacheTTL
        self.requestTimeout = requestTimeout
    }
}
