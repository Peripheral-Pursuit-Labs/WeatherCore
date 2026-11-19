import Testing
import Foundation
@testable import WeatherCore

/// Stub conforming to `WeatherKitForecasting` so we can exercise the WeatherClient
/// wiring without the WeatherKit entitlement (the native client needs it at runtime).
final class MockWeatherKitClient: WeatherKitForecasting, @unchecked Sendable {
    enum Outcome: Sendable {
        case success
        case failure(ProviderError)
    }

    let outcome: Outcome
    private(set) var receivedHorizon: ForecastHorizon?

    init(outcome: Outcome = .success) {
        self.outcome = outcome
    }

    static let stubAttribution = WeatherKitAttribution(
        serviceName: "Apple Weather",
        legalPageURL: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!,
        combinedMarkLightURL: URL(string: "https://example.com/light.png")!,
        combinedMarkDarkURL: URL(string: "https://example.com/dark.png")!,
        squareMarkURL: URL(string: "https://example.com/square.png")!
    )

    func attribution() async throws -> WeatherKitAttribution {
        if case .failure(let error) = outcome { throw error }
        return Self.stubAttribution
    }

    func forecast(at coord: Coordinate, horizon: ForecastHorizon, units: UnitSystem) async throws -> ProviderForecast {
        receivedHorizon = horizon
        switch outcome {
        case .failure(let error):
            throw error
        case .success:
            let now = Date()
            let snapshots = (0..<24).map { i in
                WeatherSnapshot(
                    time: now.addingTimeInterval(TimeInterval(i * 3600)),
                    precipitationIntensity: Measurement(value: 0.2, unit: UnitPrecipitationIntensity.millimetersPerHour),
                    precipitationProbability: 0.8
                )
            }
            return ProviderForecast(
                provider: .weatherKit,
                fetchedAt: now,
                current: nil,
                minutely: nil,
                hourly: HourlyForecast(snapshots: snapshots),
                daily: nil,
                extras: .weatherKit(WeatherKitExtras(symbolName: "cloud.rain", conditionDescription: "Rain"))
            )
        }
    }
}

@Suite("WeatherKit folds into the unified forecast and disagreement analysis")
struct WeatherKitTests {

    private let coord = Coordinate(latitude: 28.8, longitude: -81.27)

    @Test func weatherKitIsConsideredInDisagreementAlongsideOtherForecastProviders() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        let client = WeatherClient(
            config: WeatherClientConfig(),
            http: mock,
            weatherKit: MockWeatherKitClient()
        )

        let result = await client.unifiedForecast(
            at: coord,
            horizon: .hourly,
            providers: [.openMeteo, .weatherKit]
        )

        #expect(result.perProvider[.weatherKit] != nil)
        #expect(result.perProvider[.openMeteo] != nil)
        // The whole point: WeatherKit is now a third forecast source the analyzer compares.
        #expect(result.disagreement.providersConsidered.contains(.weatherKit))
        #expect(result.disagreement.providersConsidered.contains(.openMeteo))
        #expect(result.disagreement.providersConsidered.count == 2)
    }

    @Test func weatherKitReceivesTheRequestedHorizon() async {
        let mock = MockHTTPClient()
        let wk = MockWeatherKitClient()
        let client = WeatherClient(config: WeatherClientConfig(), http: mock, weatherKit: wk)

        _ = await client.unifiedForecast(at: coord, horizon: .nextHour, providers: [.weatherKit])

        #expect(wk.receivedHorizon == .nextHour)
    }

    @Test func weatherKitFailureIsCapturedNotThrown() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        let client = WeatherClient(
            config: WeatherClientConfig(),
            http: mock,
            weatherKit: MockWeatherKitClient(outcome: .failure(.noData))
        )

        let result = await client.unifiedForecast(at: coord, providers: [.openMeteo, .weatherKit])

        #expect(result.perProvider[.weatherKit] == nil)
        #expect(result.failures[.weatherKit] != nil)
        #expect(result.perProvider[.openMeteo] != nil)
    }

    @Test func attributionIsReturnedWhenWeatherKitIsConfigured() async throws {
        let client = WeatherClient(
            config: WeatherClientConfig(),
            http: MockHTTPClient(),
            weatherKit: MockWeatherKitClient()
        )

        let attribution = try await client.weatherKitAttribution()

        #expect(attribution?.serviceName == "Apple Weather")
        #expect(attribution?.legalPageURL.absoluteString.contains("apple.com") == true)
    }

    @Test func attributionIsNilWhenWeatherKitIsNotConfigured() async throws {
        let client = WeatherClient(config: WeatherClientConfig(), http: MockHTTPClient())

        let attribution = try await client.weatherKitAttribution()

        #expect(attribution == nil)
    }

    @Test func weatherKitIsSkippedWhenNotConfigured() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        // No injected client, config flag off → WeatherKit absent without producing a failure.
        let client = WeatherClient(config: WeatherClientConfig(), http: mock)

        let result = await client.unifiedForecast(at: coord, providers: [.openMeteo, .weatherKit])

        #expect(result.perProvider[.weatherKit] == nil)
        #expect(result.failures[.weatherKit] == nil)
    }
}
