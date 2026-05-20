import Foundation

/// Result of a unified multi-provider query. Disagreement is computed automatically.
public struct UnifiedForecast: Sendable {
    public let coordinate: Coordinate
    public let requestedAt: Date
    public let horizon: ForecastHorizon
    public let perProvider: [ProviderID: ProviderForecast]
    public let failures: [ProviderID: ProviderError]
    public let disagreement: DisagreementReport
    public let alerts: [WeatherAlert]

    public init(
        coordinate: Coordinate,
        requestedAt: Date,
        horizon: ForecastHorizon,
        perProvider: [ProviderID: ProviderForecast],
        failures: [ProviderID: ProviderError],
        disagreement: DisagreementReport,
        alerts: [WeatherAlert]
    ) {
        self.coordinate = coordinate
        self.requestedAt = requestedAt
        self.horizon = horizon
        self.perProvider = perProvider
        self.failures = failures
        self.disagreement = disagreement
        self.alerts = alerts
    }
}

/// Cross-provider analysis. Quantifies how much providers disagree about precipitation
/// across the requested horizon, plus consensus values where possible.
public struct DisagreementReport: Sendable, Codable {
    public enum Level: String, Sendable, Codable {
        case none           // <1 provider with data, or all agree closely
        case low            // qualitative agreement (all rain or all dry)
        case moderate       // type agreement, intensity disagreement
        case high           // disagreement about whether precip is occurring at all
    }

    public struct WindowDisagreement: Sendable, Codable {
        public let window: DateInterval
        /// Probability of precipitation per provider in this window.
        public let probabilityByProvider: [ProviderID: Double]
        /// Mean intensity (mm/hr) per provider in this window.
        public let intensityByProvider: [ProviderID: Double]
        /// Spread (max - min) of probabilities. Higher = more disagreement.
        public let probabilitySpread: Double
        public let level: Level

        public init(
            window: DateInterval,
            probabilityByProvider: [ProviderID: Double],
            intensityByProvider: [ProviderID: Double],
            probabilitySpread: Double,
            level: Level
        ) {
            self.window = window
            self.probabilityByProvider = probabilityByProvider
            self.intensityByProvider = intensityByProvider
            self.probabilitySpread = probabilitySpread
            self.level = level
        }
    }

    public let overallLevel: Level
    public let windows: [WindowDisagreement]
    /// Median across providers per window — usable as a consensus forecast.
    public let consensus: [DateInterval: Double]
    public let providersConsidered: [ProviderID]

    public init(
        overallLevel: Level,
        windows: [WindowDisagreement],
        consensus: [DateInterval: Double],
        providersConsidered: [ProviderID]
    ) {
        self.overallLevel = overallLevel
        self.windows = windows
        self.consensus = consensus
        self.providersConsidered = providersConsidered
    }

    public static let empty = DisagreementReport(
        overallLevel: .none,
        windows: [],
        consensus: [:],
        providersConsidered: []
    )
}
