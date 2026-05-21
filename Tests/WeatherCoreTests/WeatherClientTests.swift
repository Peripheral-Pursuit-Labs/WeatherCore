import Testing
import Foundation
@testable import WeatherCore

@Suite("WeatherClient orchestrates providers and computes disagreement")
struct WeatherClientTests {

    @Test func unifiedForecastFansOutAndAggregatesSuccesses() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("pirateweather.net", with: .init(data: Fixtures.data(Fixtures.pirateWeatherSample)))
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))
        mock.stubURLContaining("rainviewer.com", with: .init(data: Fixtures.data(Fixtures.rainViewerSample)))
        mock.stubURLContaining("weather.gov", with: .init(data: Fixtures.data(Fixtures.nwsAlertsSample)))

        let config = WeatherClientConfig(
            pirateWeatherAPIKey: "test-key",
            nwsUserAgent: "TestApp/1.0"
        )
        let client = WeatherClient(config: config, http: mock)

        let result = await client.unifiedForecast(
            at: Coordinate(latitude: 28.8, longitude: -81.27),
            horizon: .hourly
        )

        #expect(result.perProvider.count == 4)
        #expect(result.failures.isEmpty)
        #expect(result.alerts.count == 1)
        #expect(result.alerts.first?.severity == .severe)
    }

    @Test func unifiedForecastCapturesPartialFailures() async {
        let mock = MockHTTPClient()
        // Pirate fails, others succeed
        mock.stubURLContaining("pirateweather.net", with: .init(data: Data("upstream timeout".utf8), statusCode: 503))
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))
        mock.stubURLContaining("rainviewer.com", with: .init(data: Fixtures.data(Fixtures.rainViewerSample)))
        mock.stubURLContaining("weather.gov", with: .init(data: Fixtures.data(Fixtures.nwsAlertsSample)))

        let config = WeatherClientConfig(
            pirateWeatherAPIKey: "test-key",
            nwsUserAgent: "TestApp/1.0"
        )
        let client = WeatherClient(config: config, http: mock)

        let result = await client.unifiedForecast(at: Coordinate(latitude: 28.8, longitude: -81.27))

        #expect(result.perProvider[.pirateWeather] == nil)
        #expect(result.failures[.pirateWeather] != nil)
        #expect(result.perProvider[.openMeteo] != nil)
    }

    @Test func unifiedForecastSkipsUnconfiguredProviders() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))
        mock.stubURLContaining("rainviewer.com", with: .init(data: Fixtures.data(Fixtures.rainViewerSample)))

        // No PW key, no NWS UA
        let config = WeatherClientConfig()
        let client = WeatherClient(config: config, http: mock)

        let result = await client.unifiedForecast(at: Coordinate(latitude: 28.8, longitude: -81.27))

        #expect(result.perProvider[.pirateWeather] == nil)
        #expect(result.perProvider[.nws] == nil)
        #expect(result.failures[.pirateWeather] == nil, "Skipped providers shouldn't produce failures")
        #expect(result.failures[.nws] == nil)
        #expect(result.perProvider[.openMeteo] != nil)
        #expect(result.perProvider[.rainViewer] != nil)
    }

    @Test func retryPolicyFromConfigRetriesTransientFailures() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("pirateweather.net", with: .init(data: Data("upstream error".utf8), statusCode: 503))
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        let config = WeatherClientConfig(
            pirateWeatherAPIKey: "test-key",
            retryPolicy: RetryPolicy(maxRetries: 2, baseDelay: 0.001, jitter: 0)
        )
        let client = WeatherClient(config: config, http: mock)

        let result = await client.unifiedForecast(
            at: Coordinate(latitude: 28.8, longitude: -81.27),
            providers: [.pirateWeather, .openMeteo]
        )

        let pirateCalls = mock.requests.filter { $0.url?.host?.contains("pirateweather") == true }.count
        #expect(pirateCalls == 3, "1 initial + 2 retries on 503")
        #expect(result.failures[.pirateWeather] != nil, "still fails after exhausting retries")
        #expect(result.perProvider[.openMeteo] != nil)
    }

    @Test func unifiedForecastRespectsProviderFilter() async {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        let config = WeatherClientConfig(pirateWeatherAPIKey: "test", nwsUserAgent: "TestApp/1.0")
        let client = WeatherClient(config: config, http: mock)

        let result = await client.unifiedForecast(
            at: Coordinate(latitude: 28.8, longitude: -81.27),
            providers: [.openMeteo]
        )

        #expect(result.perProvider.count == 1)
        #expect(result.perProvider[.openMeteo] != nil)
    }
}
