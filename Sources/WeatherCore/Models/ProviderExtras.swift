import Foundation

/// Provider-specific data that doesn't fit the normalized model.
/// Consumers reach in here when they need CAPE, ensemble spread, or model attribution.
public enum ProviderExtras: Sendable {
    case pirateWeather(PirateWeatherExtras)
    case openMeteo(OpenMeteoExtras)
    case weatherKit(WeatherKitExtras)
    case rainViewer(RainViewerExtras)
    case nws(NWSExtras)
    case none
}

public struct PirateWeatherExtras: Sendable, Codable {
    /// Convective Available Potential Energy in J/kg. >2500 implies thunderstorm potential.
    public let cape: Double?
    /// Which underlying model produced each field (e.g. "hrrr", "nbm", "gfs").
    public let sourceAttribution: [String: String]
    public let processingTimeMs: Double?

    public init(cape: Double? = nil, sourceAttribution: [String: String] = [:], processingTimeMs: Double? = nil) {
        self.cape = cape
        self.sourceAttribution = sourceAttribution
        self.processingTimeMs = processingTimeMs
    }
}

public struct OpenMeteoExtras: Sendable, Codable {
    /// When multiple models were requested, per-model hourly precipitation in mm/hr keyed by model ID.
    public let perModelPrecipitation: [String: [Double?]]
    /// Hourly timestamps corresponding to perModelPrecipitation values.
    public let hourlyTimes: [Date]
    public let modelsRequested: [String]

    public init(
        perModelPrecipitation: [String: [Double?]] = [:],
        hourlyTimes: [Date] = [],
        modelsRequested: [String] = []
    ) {
        self.perModelPrecipitation = perModelPrecipitation
        self.hourlyTimes = hourlyTimes
        self.modelsRequested = modelsRequested
    }
}

public struct WeatherKitExtras: Sendable, Codable {
    /// SF Symbol name for the current condition (e.g. "cloud.rain").
    public let symbolName: String?
    /// Human-readable current condition (e.g. "Mostly Cloudy").
    public let conditionDescription: String?
    /// When Apple considers this data set stale; useful for cache/refresh decisions.
    public let metadataExpirationDate: Date?

    public init(
        symbolName: String? = nil,
        conditionDescription: String? = nil,
        metadataExpirationDate: Date? = nil
    ) {
        self.symbolName = symbolName
        self.conditionDescription = conditionDescription
        self.metadataExpirationDate = metadataExpirationDate
    }
}

public struct RainViewerExtras: Sendable, Codable {
    public let radarFrames: [RadarFrame]
    public let nowcastFrames: [RadarFrame]
    public let host: String

    public init(radarFrames: [RadarFrame], nowcastFrames: [RadarFrame], host: String) {
        self.radarFrames = radarFrames
        self.nowcastFrames = nowcastFrames
        self.host = host
    }
}

public struct NWSExtras: Sendable, Codable {
    public let alerts: [WeatherAlert]
    public let gridpointOffice: String?
    public let forecastZone: String?

    public init(alerts: [WeatherAlert], gridpointOffice: String? = nil, forecastZone: String? = nil) {
        self.alerts = alerts
        self.gridpointOffice = gridpointOffice
        self.forecastZone = forecastZone
    }
}
