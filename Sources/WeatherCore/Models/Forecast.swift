import Foundation

/// Snapshot of conditions at a moment in time.
public struct WeatherSnapshot: Sendable, Codable {
    public let time: Date
    public let temperature: Measurement<UnitTemperature>?
    public let apparentTemperature: Measurement<UnitTemperature>?
    public let humidity: Double?            // 0...1
    public let precipitationIntensity: Measurement<UnitPrecipitationIntensity>?
    public let precipitationProbability: Double?  // 0...1
    public let precipitationType: PrecipitationType?
    public let windSpeed: Measurement<UnitSpeed>?
    public let windGust: Measurement<UnitSpeed>?
    public let windDirection: Measurement<UnitAngle>?
    public let cloudCover: Double?          // 0...1
    public let pressure: Measurement<UnitPressure>?
    public let uvIndex: Double?
    public let visibility: Measurement<UnitLength>?
    /// Convective available potential energy in joules per kilogram.
    public let cape: Double?

    public init(
        time: Date,
        temperature: Measurement<UnitTemperature>? = nil,
        apparentTemperature: Measurement<UnitTemperature>? = nil,
        humidity: Double? = nil,
        precipitationIntensity: Measurement<UnitPrecipitationIntensity>? = nil,
        precipitationProbability: Double? = nil,
        precipitationType: PrecipitationType? = nil,
        windSpeed: Measurement<UnitSpeed>? = nil,
        windGust: Measurement<UnitSpeed>? = nil,
        windDirection: Measurement<UnitAngle>? = nil,
        cloudCover: Double? = nil,
        pressure: Measurement<UnitPressure>? = nil,
        uvIndex: Double? = nil,
        visibility: Measurement<UnitLength>? = nil,
        cape: Double? = nil
    ) {
        self.time = time
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.precipitationIntensity = precipitationIntensity
        self.precipitationProbability = precipitationProbability
        self.precipitationType = precipitationType
        self.windSpeed = windSpeed
        self.windGust = windGust
        self.windDirection = windDirection
        self.cloudCover = cloudCover
        self.pressure = pressure
        self.uvIndex = uvIndex
        self.visibility = visibility
        self.cape = cape
    }
}

/// Point-in-time precipitation for the 0-60 minute window.
public struct MinutelyPoint: Sendable, Codable {
    public let time: Date
    public let intensity: Measurement<UnitPrecipitationIntensity>?
    public let probability: Double?

    public init(time: Date, intensity: Measurement<UnitPrecipitationIntensity>?, probability: Double?) {
        self.time = time
        self.intensity = intensity
        self.probability = probability
    }
}

public struct MinutelyForecast: Sendable, Codable {
    public let points: [MinutelyPoint]
    public let summary: String?

    public init(points: [MinutelyPoint], summary: String? = nil) {
        self.points = points
        self.summary = summary
    }
}

public struct HourlyForecast: Sendable, Codable {
    public let snapshots: [WeatherSnapshot]
    public init(snapshots: [WeatherSnapshot]) { self.snapshots = snapshots }
}

public struct DailySnapshot: Sendable, Codable {
    public let date: Date
    public let high: Measurement<UnitTemperature>?
    public let low: Measurement<UnitTemperature>?
    public let precipitationProbability: Double?
    public let precipitationAccumulation: Measurement<UnitLength>?
    public let precipitationType: PrecipitationType?
    public let sunrise: Date?
    public let sunset: Date?
    public let summary: String?

    public init(
        date: Date,
        high: Measurement<UnitTemperature>?,
        low: Measurement<UnitTemperature>?,
        precipitationProbability: Double?,
        precipitationAccumulation: Measurement<UnitLength>?,
        precipitationType: PrecipitationType?,
        sunrise: Date?,
        sunset: Date?,
        summary: String?
    ) {
        self.date = date
        self.high = high
        self.low = low
        self.precipitationProbability = precipitationProbability
        self.precipitationAccumulation = precipitationAccumulation
        self.precipitationType = precipitationType
        self.sunrise = sunrise
        self.sunset = sunset
        self.summary = summary
    }
}

public struct DailyForecast: Sendable, Codable {
    public let days: [DailySnapshot]
    public init(days: [DailySnapshot]) { self.days = days }
}

/// A normalized forecast from a single provider, with the raw provider payload preserved.
public struct ProviderForecast: Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    public let current: WeatherSnapshot?
    public let minutely: MinutelyForecast?
    public let hourly: HourlyForecast?
    public let daily: DailyForecast?
    public let extras: ProviderExtras

    public init(
        provider: ProviderID,
        fetchedAt: Date,
        current: WeatherSnapshot?,
        minutely: MinutelyForecast?,
        hourly: HourlyForecast?,
        daily: DailyForecast?,
        extras: ProviderExtras
    ) {
        self.provider = provider
        self.fetchedAt = fetchedAt
        self.current = current
        self.minutely = minutely
        self.hourly = hourly
        self.daily = daily
        self.extras = extras
    }
}
