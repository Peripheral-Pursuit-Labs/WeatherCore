import Foundation
import OSLog

public struct OpenMeteoClient: Sendable {
    public enum Model: String, Sendable, CaseIterable, Codable {
        case best                 // Open-Meteo's auto-selected best model
        case gfsHrrr              = "gfs_hrrr"
        case gfsGlobal            = "gfs_global"
        case ecmwfIfs04           = "ecmwf_ifs04"
        case ecmwfIfs025          = "ecmwf_ifs025"
        case iconD2               = "icon_d2"
        case iconEu               = "icon_eu"
        case meteofranceArome     = "meteofrance_arome_france_hd"

        var apiValue: String {
            self == .best ? "best_match" : rawValue
        }
    }

    private let http: any HTTPClient
    private let cache: ResponseCache?
    private let baseURL = URL(string: "https://api.open-meteo.com/v1/forecast")!

    public init(http: any HTTPClient = URLSessionHTTPClient(), cache: ResponseCache? = nil) {
        self.http = http
        self.cache = cache
    }

    public func forecast(
        at coord: Coordinate,
        units: UnitSystem = .imperial,
        models: [Model] = [.best],
        includeMinutely: Bool = true
    ) async throws -> ProviderForecast {
        let log = WeatherLog.openMeteo

        let tempUnitParam = units == .metric ? "celsius" : "fahrenheit"
        let windUnitParam = units == .metric ? "ms" : "mph"
        let precipUnitParam = units == .metric ? "mm" : "inch"

        let hourlyVars = "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,precipitation_probability,weathercode,cloudcover,windspeed_10m,windgusts_10m,winddirection_10m,pressure_msl,visibility,uv_index"
        let dailyVars = "temperature_2m_max,temperature_2m_min,precipitation_sum,precipitation_probability_max,sunrise,sunset,weathercode"
        let currentVars = "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weathercode,cloudcover,windspeed_10m,windgusts_10m,winddirection_10m,pressure_msl"

        var queryItems: [URLQueryItem] = [
            .init(name: "latitude", value: String(coord.latitude)),
            .init(name: "longitude", value: String(coord.longitude)),
            .init(name: "current", value: currentVars),
            .init(name: "hourly", value: hourlyVars),
            .init(name: "daily", value: dailyVars),
            .init(name: "temperature_unit", value: tempUnitParam),
            .init(name: "windspeed_unit", value: windUnitParam),
            .init(name: "precipitation_unit", value: precipUnitParam),
            .init(name: "timezone", value: "UTC"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "models", value: models.map(\.apiValue).joined(separator: ","))
        ]
        if includeMinutely {
            queryItems.append(.init(name: "minutely_15", value: "precipitation,precipitation_probability"))
        }

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw ProviderError.invalidURL }

        let cacheKey = "openmeteo:\(coord.latitude),\(coord.longitude):\(models.map(\.rawValue).joined(separator: ","))"
        let data: Data
        if let cached = await cache?.get(cacheKey) {
            log.debug("Cache hit for \(cacheKey, privacy: .public)")
            data = cached
        } else {
            log.debug("Fetching \(url.absoluteString, privacy: .public)")
            let request = URLRequest(url: url, timeoutInterval: 15)
            let (responseData, http) = try await self.http.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                log.error("HTTP \(http.statusCode)")
                throw ProviderError.http(status: http.statusCode, body: String(data: responseData, encoding: .utf8))
            }
            data = responseData
            await cache?.set(cacheKey, data: data)
        }

        let decoded: OpenMeteoResponse
        do {
            decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
        } catch {
            log.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw ProviderError.decoding(message: error.localizedDescription)
        }

        return decoded.toProviderForecast(units: units, modelsRequested: models)
    }
}

// MARK: - Wire format

private struct OpenMeteoResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let current: Current?
    let hourly: Hourly?
    let minutely_15: Minutely?
    let daily: Daily?

    struct Current: Decodable {
        let time: TimeInterval
        let temperature_2m: Double?
        let relative_humidity_2m: Double?
        let apparent_temperature: Double?
        let precipitation: Double?
        let weathercode: Int?
        let cloudcover: Double?
        let windspeed_10m: Double?
        let windgusts_10m: Double?
        let winddirection_10m: Double?
        let pressure_msl: Double?
    }

    struct Hourly: Decodable {
        let time: [TimeInterval]
        let temperature_2m: [Double?]?
        let relative_humidity_2m: [Double?]?
        let apparent_temperature: [Double?]?
        let precipitation: [Double?]?
        let precipitation_probability: [Double?]?
        let weathercode: [Int?]?
        let cloudcover: [Double?]?
        let windspeed_10m: [Double?]?
        let windgusts_10m: [Double?]?
        let winddirection_10m: [Double?]?
        let pressure_msl: [Double?]?
        let visibility: [Double?]?
        let uv_index: [Double?]?
    }

    struct Minutely: Decodable {
        let time: [TimeInterval]
        let precipitation: [Double?]?
        let precipitation_probability: [Double?]?
    }

    struct Daily: Decodable {
        let time: [TimeInterval]
        let temperature_2m_max: [Double?]?
        let temperature_2m_min: [Double?]?
        let precipitation_sum: [Double?]?
        let precipitation_probability_max: [Double?]?
        let sunrise: [TimeInterval?]?
        let sunset: [TimeInterval?]?
        let weathercode: [Int?]?
    }

    func toProviderForecast(units: UnitSystem, modelsRequested: [OpenMeteoClient.Model]) -> ProviderForecast {
        let tempUnit: UnitTemperature = units == .metric ? .celsius : .fahrenheit
        let speedUnit: UnitSpeed = units == .metric ? .metersPerSecond : .milesPerHour
        let precipUnit: UnitSpeed = units == .metric ? .metersPerSecond : .milesPerHour // intensity uses speed-like dimension

        // current
        let currentSnap = current.map { c in
            WeatherSnapshot(
                time: Date(timeIntervalSince1970: c.time),
                temperature: c.temperature_2m.map { Measurement(value: $0, unit: tempUnit) },
                apparentTemperature: c.apparent_temperature.map { Measurement(value: $0, unit: tempUnit) },
                humidity: c.relative_humidity_2m.map { $0 / 100 },
                precipitationIntensity: c.precipitation.map { Measurement(value: $0, unit: precipUnit) },
                precipitationProbability: nil,
                precipitationType: weatherCodeToType(c.weathercode),
                windSpeed: c.windspeed_10m.map { Measurement(value: $0, unit: speedUnit) },
                windGust: c.windgusts_10m.map { Measurement(value: $0, unit: speedUnit) },
                windDirection: c.winddirection_10m.map { Measurement(value: $0, unit: .degrees) },
                cloudCover: c.cloudcover.map { $0 / 100 },
                pressure: c.pressure_msl.map { Measurement(value: $0, unit: .hectopascals) },
                uvIndex: nil,
                visibility: nil
            )
        }

        // hourly
        let hourlySnaps: [WeatherSnapshot] = hourly.map { h in
            h.time.indices.map { i in
                // Helper to safely extract from [T?]? at index i, returning T?
                func at<T>(_ array: [T?]?) -> T? { (array?[i]) ?? nil }

                return WeatherSnapshot(
                    time: Date(timeIntervalSince1970: h.time[i]),
                    temperature: at(h.temperature_2m).map { Measurement(value: $0, unit: tempUnit) },
                    apparentTemperature: at(h.apparent_temperature).map { Measurement(value: $0, unit: tempUnit) },
                    humidity: at(h.relative_humidity_2m).map { $0 / 100 },
                    precipitationIntensity: at(h.precipitation).map { Measurement(value: $0, unit: precipUnit) },
                    precipitationProbability: at(h.precipitation_probability).map { $0 / 100 },
                    precipitationType: weatherCodeToType(at(h.weathercode)),
                    windSpeed: at(h.windspeed_10m).map { Measurement(value: $0, unit: speedUnit) },
                    windGust: at(h.windgusts_10m).map { Measurement(value: $0, unit: speedUnit) },
                    windDirection: at(h.winddirection_10m).map { Measurement(value: $0, unit: .degrees) },
                    cloudCover: at(h.cloudcover).map { $0 / 100 },
                    pressure: at(h.pressure_msl).map { Measurement(value: $0, unit: .hectopascals) },
                    uvIndex: at(h.uv_index),
                    visibility: at(h.visibility).map { Measurement(value: $0, unit: .meters) }
                )
            }
        } ?? []

        // minutely (15-min granularity)
        let minutelyPoints = minutely_15.map { m in
            m.time.indices.map { i in
                func at<T>(_ array: [T?]?) -> T? { (array?[i]) ?? nil }
                return MinutelyPoint(
                    time: Date(timeIntervalSince1970: m.time[i]),
                    intensity: at(m.precipitation).map { Measurement(value: $0, unit: precipUnit) },
                    probability: at(m.precipitation_probability).map { $0 / 100 }
                )
            }
        }

        // daily
        let dailySnaps: [DailySnapshot] = daily.map { d in
            d.time.indices.map { i in
                func at<T>(_ array: [T?]?) -> T? { (array?[i]) ?? nil }
                return DailySnapshot(
                    date: Date(timeIntervalSince1970: d.time[i]),
                    high: at(d.temperature_2m_max).map { Measurement(value: $0, unit: tempUnit) },
                    low: at(d.temperature_2m_min).map { Measurement(value: $0, unit: tempUnit) },
                    precipitationProbability: at(d.precipitation_probability_max).map { $0 / 100 },
                    precipitationAccumulation: at(d.precipitation_sum).map { Measurement(value: $0, unit: .millimeters) },
                    precipitationType: weatherCodeToType(at(d.weathercode)),
                    sunrise: at(d.sunrise).map(Date.init(timeIntervalSince1970:)),
                    sunset: at(d.sunset).map(Date.init(timeIntervalSince1970:)),
                    summary: nil
                )
            }
        } ?? []

        let extras = OpenMeteoExtras(
            perModelPrecipitation: [:], // Filled when multi-model variant is parsed; single-model returns plain arrays
            hourlyTimes: hourly?.time.map(Date.init(timeIntervalSince1970:)) ?? [],
            modelsRequested: modelsRequested.map(\.rawValue)
        )

        return ProviderForecast(
            provider: .openMeteo,
            fetchedAt: Date(),
            current: currentSnap,
            minutely: minutelyPoints.map { MinutelyForecast(points: $0) },
            hourly: HourlyForecast(snapshots: hourlySnaps),
            daily: DailyForecast(days: dailySnaps),
            extras: .openMeteo(extras)
        )
    }

    private func weatherCodeToType(_ code: Int?) -> PrecipitationType? {
        guard let code else { return nil }
        // WMO weather codes
        switch code {
        case 0...3: return PrecipitationType.none
        case 51...67, 80...82: return .rain
        case 71...77, 85...86: return .snow
        case 95...99: return .rain  // thunderstorm → rain
        default: return .unknown
        }
    }
}
