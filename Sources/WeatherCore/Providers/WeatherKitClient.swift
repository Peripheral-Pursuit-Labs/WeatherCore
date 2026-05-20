import Foundation

/// Abstraction over Apple's WeatherKit so `WeatherClient` can fan out to it like any
/// other provider — and so tests can inject a stub without the WeatherKit entitlement.
///
/// Unlike the HTTP-backed providers, WeatherKit is the native framework and bypasses
/// `HTTPClient`. The horizon is passed through so the implementation can request only
/// the data sets it needs (WeatherKit bills per data set requested).
public protocol WeatherKitForecasting: Sendable {
    func forecast(at coord: Coordinate, horizon: ForecastHorizon, units: UnitSystem) async throws -> ProviderForecast
}

#if canImport(WeatherKit)
import WeatherKit
import CoreLocation

/// Native WeatherKit provider. Wraps `WeatherService` and normalizes its data sets into
/// the shared `ProviderForecast` shape. Requires the WeatherKit entitlement at runtime.
public struct WeatherKitClient: WeatherKitForecasting {
    private let service: WeatherService

    public init(service: WeatherService = .shared) {
        self.service = service
    }

    public func forecast(
        at coord: Coordinate,
        horizon: ForecastHorizon,
        units: UnitSystem
    ) async throws -> ProviderForecast {
        let log = WeatherLog.weatherKit
        let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        log.debug("Fetching WeatherKit \(String(describing: horizon)) for \(coord.latitude),\(coord.longitude)")

        do {
            // Request only the data sets the horizon needs — each one counts against quota.
            switch horizon {
            case .nextHour:
                let (current, minute) = try await service.weather(for: location, including: .current, .minute)
                return Self.map(current: current, minute: minute, hourly: nil, daily: nil, units: units)
            case .hourly:
                let (current, hourly) = try await service.weather(for: location, including: .current, .hourly)
                return Self.map(current: current, minute: nil, hourly: hourly, daily: nil, units: units)
            case .daily:
                let (current, daily) = try await service.weather(for: location, including: .current, .daily)
                return Self.map(current: current, minute: nil, hourly: nil, daily: daily, units: units)
            }
        } catch {
            log.error("WeatherKit fetch failed: \(error.localizedDescription, privacy: .public)")
            throw ProviderError.underlying(message: error.localizedDescription)
        }
    }

    // MARK: - Normalization

    private static func map(
        current: CurrentWeather,
        minute: Forecast<MinuteWeather>?,
        hourly: Forecast<HourWeather>?,
        daily: Forecast<DayWeather>?,
        units: UnitSystem
    ) -> ProviderForecast {
        let tempUnit: UnitTemperature = units == .metric ? .celsius : .fahrenheit
        let speedUnit: UnitSpeed = units == .metric ? .metersPerSecond : .milesPerHour
        let lengthUnit: UnitLength = units == .metric ? .kilometers : .miles

        let currentSnapshot = WeatherSnapshot(
            time: current.date,
            temperature: current.temperature.converted(to: tempUnit),
            apparentTemperature: current.apparentTemperature.converted(to: tempUnit),
            humidity: current.humidity,
            // WeatherKit reports intensity as a Measurement<UnitSpeed>; the analyzer
            // converts to mm/hr, so pass it through unchanged.
            precipitationIntensity: current.precipitationIntensity,
            precipitationProbability: nil,   // not exposed on CurrentWeather
            precipitationType: nil,
            windSpeed: current.wind.speed.converted(to: speedUnit),
            windGust: current.wind.gust?.converted(to: speedUnit),
            windDirection: current.wind.direction,
            cloudCover: current.cloudCover,
            pressure: current.pressure,
            uvIndex: Double(current.uvIndex.value),
            visibility: current.visibility.converted(to: lengthUnit)
        )

        let minutelyForecast = minute.map { forecast in
            MinutelyForecast(
                points: forecast.forecast.map { m in
                    MinutelyPoint(
                        time: m.date,
                        intensity: m.precipitationIntensity,
                        probability: m.precipitationChance
                    )
                },
                summary: nil
            )
        }

        let hourlyForecast = hourly.map { forecast in
            HourlyForecast(snapshots: forecast.forecast.map { h in
                WeatherSnapshot(
                    time: h.date,
                    temperature: h.temperature.converted(to: tempUnit),
                    apparentTemperature: h.apparentTemperature.converted(to: tempUnit),
                    humidity: h.humidity,
                    // HourWeather exposes accumulation over the hour, not a rate.
                    // mm over one hour equals mm/hr numerically.
                    precipitationIntensity: Measurement(
                        value: h.precipitationAmount.converted(to: .millimeters).value,
                        unit: .millimetersPerHour
                    ),
                    precipitationProbability: h.precipitationChance,
                    precipitationType: mapPrecip(h.precipitation),
                    windSpeed: h.wind.speed.converted(to: speedUnit),
                    windGust: h.wind.gust?.converted(to: speedUnit),
                    windDirection: h.wind.direction,
                    cloudCover: h.cloudCover,
                    pressure: h.pressure,
                    uvIndex: Double(h.uvIndex.value),
                    visibility: h.visibility.converted(to: lengthUnit)
                )
            })
        }

        let dailyForecast = daily.map { forecast in
            DailyForecast(days: forecast.forecast.map { d in
                DailySnapshot(
                    date: d.date,
                    high: d.highTemperature.converted(to: tempUnit),
                    low: d.lowTemperature.converted(to: tempUnit),
                    precipitationProbability: d.precipitationChance,
                    precipitationAccumulation: Measurement(
                        value: d.precipitationAmountByType.precipitation.converted(to: .millimeters).value,
                        unit: .millimeters
                    ),
                    precipitationType: mapPrecip(d.precipitation),
                    sunrise: d.sun.sunrise,
                    sunset: d.sun.sunset,
                    summary: d.condition.description
                )
            })
        }

        let extras = WeatherKitExtras(
            symbolName: current.symbolName,
            conditionDescription: current.condition.description,
            metadataExpirationDate: current.metadata.expirationDate
        )

        return ProviderForecast(
            provider: .weatherKit,
            fetchedAt: Date(),
            current: currentSnapshot,
            minutely: minutelyForecast,
            hourly: hourlyForecast,
            daily: dailyForecast,
            extras: .weatherKit(extras)
        )
    }

    private static func mapPrecip(_ precipitation: Precipitation) -> PrecipitationType {
        switch precipitation {
        case .none: .none
        case .hail: .hail
        case .mixed: .mixed
        case .rain: .rain
        case .sleet: .sleet
        case .snow: .snow
        @unknown default: .unknown
        }
    }
}

private extension UnitSpeed {
    /// mm/hr expressed against UnitSpeed's m/s base (1 mm/hr = 1/3,600,000 m/s).
    static let millimetersPerHour = UnitSpeed(
        symbol: "mm/h",
        converter: UnitConverterLinear(coefficient: 1.0 / 3_600_000.0)
    )
}
#endif
