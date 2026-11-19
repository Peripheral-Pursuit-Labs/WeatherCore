import Foundation
import OSLog

public struct PirateWeatherClient: Sendable {
    private let apiKey: String
    private let http: any HTTPClient
    private let cache: ResponseCache?
    private let baseURL = URL(string: "https://api.pirateweather.net/forecast")!

    public init(apiKey: String, http: any HTTPClient = URLSessionHTTPClient(), cache: ResponseCache? = nil) {
        self.apiKey = apiKey
        self.http = http
        self.cache = cache
    }

    public func forecast(at coord: Coordinate, units: UnitSystem = .imperial) async throws -> ProviderForecast {
        let log = WeatherLog.pirate

        guard !apiKey.isEmpty else {
            log.error("Missing API key")
            throw ProviderError.missingAPIKey(.pirateWeather)
        }

        let unitsParam = units == .metric ? "si" : "us"
        let path = "\(apiKey)/\(coord.latitude),\(coord.longitude)"
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "units", value: unitsParam),
            URLQueryItem(name: "version", value: "2")
        ]
        guard let url = components.url else { throw ProviderError.invalidURL }

        let cacheKey = "pirate:\(coord.latitude),\(coord.longitude):\(unitsParam)"
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

        let decoded: PirateResponse
        do {
            let decoder = JSONDecoder()
            decoded = try decoder.decode(PirateResponse.self, from: data)
        } catch {
            log.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw ProviderError.decoding(message: error.localizedDescription)
        }

        return decoded.toProviderForecast(units: units)
    }
}

// MARK: - Wire format

private struct PirateResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let timezone: String?
    let currently: Currently?
    let minutely: Minutely?
    let hourly: Hourly?
    let daily: Daily?
    let flags: Flags?

    struct Currently: Decodable {
        let time: TimeInterval
        let temperature: Double?
        let apparentTemperature: Double?
        let humidity: Double?
        let precipIntensity: Double?
        let precipProbability: Double?
        let precipType: String?
        let windSpeed: Double?
        let windGust: Double?
        let windBearing: Double?
        let cloudCover: Double?
        let pressure: Double?
        let uvIndex: Double?
        let visibility: Double?
        let cape: Double?
    }

    struct Minutely: Decodable {
        let summary: String?
        let data: [MinutelyPoint]
        struct MinutelyPoint: Decodable {
            let time: TimeInterval
            let precipIntensity: Double?
            let precipProbability: Double?
        }
    }

    struct Hourly: Decodable {
        let data: [Currently]
    }

    struct Daily: Decodable {
        let data: [DailyPoint]
        struct DailyPoint: Decodable {
            let time: TimeInterval
            let temperatureHigh: Double?
            let temperatureLow: Double?
            let precipProbability: Double?
            let precipAccumulation: Double?
            let precipType: String?
            let sunriseTime: TimeInterval?
            let sunsetTime: TimeInterval?
            let summary: String?
        }
    }

    struct Flags: Decodable {
        let sources: [String]?
        let sourceIDX: [String: SourceAttribution]?
        let processTime: Double?
        struct SourceAttribution: Decodable {
            let x: Double?
            let y: Double?
        }
    }

    func toProviderForecast(units: UnitSystem) -> ProviderForecast {
        let tempUnit: UnitTemperature = units == .metric ? .celsius : .fahrenheit
        let speedUnit: UnitSpeed = units == .metric ? .metersPerSecond : .milesPerHour
        // Pirate Weather reports precipIntensity in mm/hr (metric) or in/hr (imperial).
        let precipUnit: UnitPrecipitationIntensity = units == .metric ? .millimetersPerHour : .inchesPerHour
        let pressureUnit: UnitPressure = .hectopascals
        let lengthUnit: UnitLength = units == .metric ? .kilometers : .miles

        let current = currently.map { c in
            WeatherSnapshot(
                time: Date(timeIntervalSince1970: c.time),
                temperature: c.temperature.map { Measurement(value: $0, unit: tempUnit) },
                apparentTemperature: c.apparentTemperature.map { Measurement(value: $0, unit: tempUnit) },
                humidity: c.humidity,
                precipitationIntensity: c.precipIntensity.map { Measurement(value: $0, unit: precipUnit) },
                precipitationProbability: c.precipProbability,
                precipitationType: mapPrecipType(c.precipType),
                windSpeed: c.windSpeed.map { Measurement(value: $0, unit: speedUnit) },
                windGust: c.windGust.map { Measurement(value: $0, unit: speedUnit) },
                windDirection: c.windBearing.map { Measurement(value: $0, unit: .degrees) },
                cloudCover: c.cloudCover,
                pressure: c.pressure.map { Measurement(value: $0, unit: pressureUnit) },
                uvIndex: c.uvIndex,
                visibility: c.visibility.map { Measurement(value: $0, unit: lengthUnit) }
            )
        }

        let minutelyForecast = minutely.map { m in
            MinutelyForecast(
                points: m.data.map { p in
                    MinutelyPoint(
                        time: Date(timeIntervalSince1970: p.time),
                        intensity: p.precipIntensity.map { Measurement(value: $0, unit: precipUnit) },
                        probability: p.precipProbability
                    )
                },
                summary: m.summary
            )
        }

        let hourlyForecast = hourly.map { h in
            HourlyForecast(snapshots: h.data.map { c in
                WeatherSnapshot(
                    time: Date(timeIntervalSince1970: c.time),
                    temperature: c.temperature.map { Measurement(value: $0, unit: tempUnit) },
                    apparentTemperature: c.apparentTemperature.map { Measurement(value: $0, unit: tempUnit) },
                    humidity: c.humidity,
                    precipitationIntensity: c.precipIntensity.map { Measurement(value: $0, unit: precipUnit) },
                    precipitationProbability: c.precipProbability,
                    precipitationType: mapPrecipType(c.precipType),
                    windSpeed: c.windSpeed.map { Measurement(value: $0, unit: speedUnit) },
                    windGust: c.windGust.map { Measurement(value: $0, unit: speedUnit) },
                    windDirection: c.windBearing.map { Measurement(value: $0, unit: .degrees) },
                    cloudCover: c.cloudCover,
                    pressure: c.pressure.map { Measurement(value: $0, unit: pressureUnit) },
                    uvIndex: c.uvIndex,
                    visibility: c.visibility.map { Measurement(value: $0, unit: lengthUnit) }
                )
            })
        }

        let dailyForecast = daily.map { d in
            DailyForecast(days: d.data.map { p in
                DailySnapshot(
                    date: Date(timeIntervalSince1970: p.time),
                    high: p.temperatureHigh.map { Measurement(value: $0, unit: tempUnit) },
                    low: p.temperatureLow.map { Measurement(value: $0, unit: tempUnit) },
                    precipitationProbability: p.precipProbability,
                    precipitationAccumulation: p.precipAccumulation.map { Measurement(value: $0, unit: .millimeters) },
                    precipitationType: mapPrecipType(p.precipType),
                    sunrise: p.sunriseTime.map(Date.init(timeIntervalSince1970:)),
                    sunset: p.sunsetTime.map(Date.init(timeIntervalSince1970:)),
                    summary: p.summary
                )
            })
        }

        let extras = PirateWeatherExtras(
            cape: currently?.cape,
            sourceAttribution: [:],
            processingTimeMs: flags?.processTime
        )

        return ProviderForecast(
            provider: .pirateWeather,
            fetchedAt: Date(),
            current: current,
            minutely: minutelyForecast,
            hourly: hourlyForecast,
            daily: dailyForecast,
            extras: .pirateWeather(extras)
        )
    }

    private func mapPrecipType(_ raw: String?) -> PrecipitationType? {
        switch raw?.lowercased() {
        case "rain": .rain
        case "snow": .snow
        case "sleet": .sleet
        case "hail": .hail
        case "none", nil: raw == nil ? nil : PrecipitationType.none
        default: .unknown
        }
    }
}
