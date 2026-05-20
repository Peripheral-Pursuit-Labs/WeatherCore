import Foundation
import OSLog

public struct WeatherClient: Sendable {
    public let config: WeatherClientConfig
    public let pirateWeather: PirateWeatherClient?
    public let openMeteo: OpenMeteoClient
    public let weatherKit: (any WeatherKitForecasting)?
    public let rainViewer: RainViewerClient
    public let nws: NWSClient?

    private let analyzer = DisagreementAnalyzer()

    /// Providers that produce comparable point forecasts and so feed disagreement analysis.
    /// RainViewer (radar) and NWS (alerts) carry no probability/intensity values to compare.
    private static let analyzableProviders: Set<ProviderID> = [.pirateWeather, .openMeteo, .weatherKit]

    public init(
        config: WeatherClientConfig,
        http: any HTTPClient = URLSessionHTTPClient(),
        weatherKit: (any WeatherKitForecasting)? = nil
    ) {
        self.config = config
        let cache = ResponseCache(defaultTTL: config.cacheTTL)

        if let key = config.pirateWeatherAPIKey, !key.isEmpty {
            self.pirateWeather = PirateWeatherClient(apiKey: key, http: http, cache: cache)
        } else {
            self.pirateWeather = nil
        }

        self.openMeteo = OpenMeteoClient(http: http, cache: cache)
        self.rainViewer = RainViewerClient(http: http, cache: cache)

        if let ua = config.nwsUserAgent, !ua.isEmpty {
            self.nws = NWSClient(userAgent: ua, http: http, cache: cache)
        } else {
            self.nws = nil
        }

        // An injected client wins (used by tests); otherwise stand up the native
        // client when the caller opted in via config.
        if let weatherKit {
            self.weatherKit = weatherKit
        } else if config.enableWeatherKit {
            #if canImport(WeatherKit)
            self.weatherKit = WeatherKitClient()
            #else
            self.weatherKit = nil
            #endif
        } else {
            self.weatherKit = nil
        }
    }

    /// The headline call. Fans out to every configured provider concurrently,
    /// computes a disagreement report across the results, and returns alerts.
    /// Providers that fail are captured in `failures` rather than thrown.
    public func unifiedForecast(
        at coord: Coordinate,
        horizon: ForecastHorizon = .hourly,
        providers: Set<ProviderID> = Set(ProviderID.allCases),
        openMeteoModels: [OpenMeteoClient.Model] = [.best]
    ) async -> UnifiedForecast {
        let log = WeatherLog.client
        let requestedAt = Date()
        log.info("Unified forecast request at \(coord.latitude),\(coord.longitude) horizon=\(String(describing: horizon))")

        async let pirateResult = fetchPirate(at: coord, enabled: providers.contains(.pirateWeather))
        async let openMeteoResult = fetchOpenMeteo(at: coord, enabled: providers.contains(.openMeteo), models: openMeteoModels)
        async let weatherKitResult = fetchWeatherKit(at: coord, horizon: horizon, enabled: providers.contains(.weatherKit))
        async let rainViewerResult = fetchRainViewer(at: coord, enabled: providers.contains(.rainViewer))
        async let nwsResult = fetchNWS(at: coord, enabled: providers.contains(.nws))

        let results = await (pirateResult, openMeteoResult, weatherKitResult, rainViewerResult, nwsResult)

        var perProvider: [ProviderID: ProviderForecast] = [:]
        var failures: [ProviderID: ProviderError] = [:]
        var alerts: [WeatherAlert] = []

        for (id, result) in [
            (ProviderID.pirateWeather, results.0),
            (ProviderID.openMeteo, results.1),
            (ProviderID.weatherKit, results.2),
            (ProviderID.rainViewer, results.3),
            (ProviderID.nws, results.4)
        ] {
            switch result {
            case .success(let forecast):
                perProvider[id] = forecast
                if case .nws(let nwsExtras) = forecast.extras {
                    alerts.append(contentsOf: nwsExtras.alerts)
                }
            case .failure(let error):
                failures[id] = error
                WeatherLog.forProvider(id).error("Provider failed: \(error.description, privacy: .public)")
            case .skipped:
                continue
            }
        }

        // RainViewer doesn't contribute to disagreement analysis (no forecast values).
        // Same for NWS (alerts only). Filter them out.
        let analyzable = perProvider.filter { Self.analyzableProviders.contains($0.key) }
        let disagreement = analyzer.analyze(
            forecasts: analyzable,
            horizon: horizon,
            referenceTime: requestedAt
        )

        log.info("Unified forecast complete: \(perProvider.count) succeeded, \(failures.count) failed, overall disagreement=\(disagreement.overallLevel.rawValue)")

        return UnifiedForecast(
            coordinate: coord,
            requestedAt: requestedAt,
            horizon: horizon,
            perProvider: perProvider,
            failures: failures,
            disagreement: disagreement,
            alerts: alerts
        )
    }

    // MARK: - Individual fetch helpers, each returning an enum so we can capture errors per-provider

    private enum FetchResult: Sendable {
        case success(ProviderForecast)
        case failure(ProviderError)
        case skipped
    }

    private func fetchPirate(at coord: Coordinate, enabled: Bool) async -> FetchResult {
        guard enabled, let client = pirateWeather else { return .skipped }
        do {
            return .success(try await client.forecast(at: coord, units: config.defaultUnits))
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.underlying(message: error.localizedDescription))
        }
    }

    private func fetchOpenMeteo(at coord: Coordinate, enabled: Bool, models: [OpenMeteoClient.Model]) async -> FetchResult {
        guard enabled else { return .skipped }
        do {
            return .success(try await openMeteo.forecast(at: coord, units: config.defaultUnits, models: models))
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.underlying(message: error.localizedDescription))
        }
    }

    private func fetchWeatherKit(at coord: Coordinate, horizon: ForecastHorizon, enabled: Bool) async -> FetchResult {
        guard enabled, let client = weatherKit else { return .skipped }
        do {
            return .success(try await client.forecast(at: coord, horizon: horizon, units: config.defaultUnits))
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.underlying(message: error.localizedDescription))
        }
    }

    private func fetchRainViewer(at coord: Coordinate, enabled: Bool) async -> FetchResult {
        guard enabled else { return .skipped }
        do {
            return .success(try await rainViewer.frames(near: coord))
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.underlying(message: error.localizedDescription))
        }
    }

    private func fetchNWS(at coord: Coordinate, enabled: Bool) async -> FetchResult {
        guard enabled, let client = nws else { return .skipped }
        do {
            return .success(try await client.alerts(at: coord))
        } catch let error as ProviderError {
            return .failure(error)
        } catch {
            return .failure(.underlying(message: error.localizedDescription))
        }
    }
}
