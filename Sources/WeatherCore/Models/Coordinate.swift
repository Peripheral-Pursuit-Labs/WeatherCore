import Foundation

public struct Coordinate: Hashable, Sendable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum UnitSystem: String, Sendable, Codable {
    case metric
    case imperial
}

public enum ForecastHorizon: Sendable {
    /// 0–60 minutes, minute-resolution where available.
    case nextHour
    /// 0–48 hours, hourly resolution.
    case hourly
    /// 0–7 days, daily aggregates.
    case daily
}

/// Identifies a forecast provider. Used in disagreement reports and per-provider failures.
public enum ProviderID: String, Sendable, Codable, CaseIterable, Hashable {
    case pirateWeather
    case openMeteo
    case rainViewer
    case nws
}

public enum PrecipitationType: String, Sendable, Codable {
    case none
    case rain
    case snow
    case sleet
    case hail
    case mixed
    case unknown
}
