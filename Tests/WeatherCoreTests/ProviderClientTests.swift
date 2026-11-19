import Testing
import Foundation
@testable import WeatherCore

@Suite("Provider clients decode wire formats correctly")
struct ProviderClientTests {

    @Test func pirateWeatherDecodesBasicResponse() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("pirateweather.net", with: .init(data: Fixtures.data(Fixtures.pirateWeatherSample)))

        let client = PirateWeatherClient(apiKey: "test-key", http: mock)
        let forecast = try await client.forecast(at: Coordinate(latitude: 28.8, longitude: -81.27))

        #expect(forecast.provider == .pirateWeather)
        #expect(forecast.current?.temperature?.value == 82.5)
        #expect(forecast.minutely?.points.count == 4)
        #expect(forecast.minutely?.summary == "Light rain starting in 12 min.")
        if case .pirateWeather(let extras) = forecast.extras {
            #expect(extras.cape == 1200)
            #expect(extras.processingTimeMs == 142.3)
        } else {
            Issue.record("Expected pirateWeather extras")
        }
    }

    @Test func pirateWeatherThrowsOnMissingKey() async throws {
        let client = PirateWeatherClient(apiKey: "", http: MockHTTPClient())
        await #expect(throws: ProviderError.self) {
            _ = try await client.forecast(at: Coordinate(latitude: 28.8, longitude: -81.27))
        }
    }

    @Test func pirateWeatherSurfacesHTTPError() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("pirateweather.net", with: .init(data: Data("rate limited".utf8), statusCode: 429))
        let client = PirateWeatherClient(apiKey: "test", http: mock)

        await #expect(throws: ProviderError.self) {
            _ = try await client.forecast(at: Coordinate(latitude: 28.8, longitude: -81.27))
        }
    }

    @Test func openMeteoDecodesMultiArrayResponse() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        let client = OpenMeteoClient(http: mock)
        let forecast = try await client.forecast(at: Coordinate(latitude: 28.8, longitude: -81.27))

        #expect(forecast.provider == .openMeteo)
        #expect(forecast.hourly?.snapshots.count == 2)
        #expect(forecast.minutely?.points.count == 4)
        #expect(forecast.daily?.days.count == 1)
        // Probability normalization 0-100 to 0-1
        #expect(forecast.hourly?.snapshots.first?.precipitationProbability == 0.45)
        #expect(forecast.hourly?.snapshots.last?.cape == 2200)
    }

    @Test func openMeteoDecodesMultiModelResponse() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoMultiModelSample)))

        let client = OpenMeteoClient(http: mock)
        let forecast = try await client.forecast(
            at: Coordinate(latitude: 28.8, longitude: -81.27),
            models: [.gfsHrrr, .ecmwfIfs04]
        )

        // The first requested model (gfs_hrrr) drives the normalized forecast.
        #expect(forecast.hourly?.snapshots.count == 2)
        #expect(forecast.hourly?.snapshots.first?.precipitationProbability == 0.45)
        #expect(forecast.hourly?.snapshots.last?.cape == 2200)
        #expect(forecast.minutely?.points.count == 4)
        #expect(forecast.daily?.days.count == 1)

        guard case .openMeteo(let extras) = forecast.extras else {
            Issue.record("Expected openMeteo extras")
            return
        }
        // Every model's hourly precipitation is exposed for intra-provider disagreement.
        #expect(extras.perModelPrecipitation.count == 2)
        #expect(extras.perModelPrecipitation["gfs_hrrr"]?.compactMap { $0 } == [2.54, 10.16])
        #expect(extras.perModelPrecipitation["ecmwf_ifs04"]?.compactMap { $0 } == [0.0, 22.86])
        #expect(extras.perModelPrecipitationProbability["gfs_hrrr"]?.compactMap { $0 } == [0.45, 0.6])
        #expect(extras.perModelPrecipitationProbability["ecmwf_ifs04"]?.compactMap { $0 } == [0.2, 0.8])
        #expect(extras.hourlyTimes.count == 2)
        #expect(extras.modelsRequested == ["gfs_hrrr", "ecmwf_ifs04"])
    }

    @Test func openMeteoRequestIncludesAllConfiguredModels() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("open-meteo.com", with: .init(data: Fixtures.data(Fixtures.openMeteoSample)))

        let client = OpenMeteoClient(http: mock)
        _ = try await client.forecast(
            at: Coordinate(latitude: 28.8, longitude: -81.27),
            models: [.gfsHrrr, .ecmwfIfs04]
        )

        let request = mock.requests.first
        #expect(request?.url?.absoluteString.contains("gfs_hrrr") == true)
        #expect(request?.url?.absoluteString.contains("ecmwf_ifs04") == true)
    }

    @Test func rainViewerDecodesPastAndNowcastFrames() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("rainviewer.com", with: .init(data: Fixtures.data(Fixtures.rainViewerSample)))

        let client = RainViewerClient(http: mock)
        let forecast = try await client.frames(near: Coordinate(latitude: 28.8, longitude: -81.27))

        if case .rainViewer(let extras) = forecast.extras {
            #expect(extras.radarFrames.count == 2)
            #expect(extras.nowcastFrames.count == 2)
            #expect(extras.host == "https://tilecache.rainviewer.com")
            #expect(extras.nowcastFrames.allSatisfy { $0.isNowcast })
        } else {
            Issue.record("Expected rainViewer extras")
        }
    }

    @Test func rainViewerTileURLConstructionMatchesAPISpec() {
        let url = RainViewerClient.tileURL(
            host: "https://tilecache.rainviewer.com",
            framePath: "/v2/radar/1716124800",
            zoom: 8,
            x: 70,
            y: 105
        )
        #expect(url?.absoluteString == "https://tilecache.rainviewer.com/v2/radar/1716124800/256/8/70/105/2/1_0.png")
    }

    @Test func nwsDecodesAlertsAndIncludesUserAgent() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("weather.gov", with: .init(data: Fixtures.data(Fixtures.nwsAlertsSample)))

        let client = NWSClient(userAgent: "TestApp/1.0 (ben@example.com)", http: mock)
        let forecast = try await client.alerts(at: Coordinate(latitude: 28.8, longitude: -81.27))

        if case .nws(let extras) = forecast.extras {
            #expect(extras.alerts.count == 1)
            #expect(extras.alerts.first?.event == "Severe Thunderstorm Warning")
            #expect(extras.alerts.first?.severity == .severe)
            #expect(extras.alerts.first?.urgency == .immediate)
        } else {
            Issue.record("Expected nws extras")
        }

        let request = mock.requests.first
        #expect(request?.value(forHTTPHeaderField: "User-Agent") == "TestApp/1.0 (ben@example.com)")
    }

    @Test func nwsFetchesLatestAreaForecastDiscussion() async throws {
        let mock = MockHTTPClient()
        mock.stubURLContaining("alerts/active", with: .init(data: Fixtures.data(Fixtures.nwsAlertsSample)))
        mock.stubURLContaining("points/", with: .init(data: Fixtures.data(Fixtures.nwsPointSample)))
        mock.stubURLContaining("products/types/AFD", with: .init(data: Fixtures.data(Fixtures.nwsProductListSample)))
        mock.stubURLContaining("products/discussion-id", with: .init(data: Fixtures.data(Fixtures.nwsProductSample)))

        let client = NWSClient(userAgent: "TestApp/1.0 (ben@example.com)", http: mock)
        let forecast = try await client.alerts(at: Coordinate(latitude: 28.8, longitude: -81.27))

        guard case .nws(let extras) = forecast.extras else {
            Issue.record("Expected nws extras")
            return
        }
        #expect(extras.gridpointOffice == "MLB")
        #expect(extras.forecastDiscussion?.office == "MLB")
        #expect(extras.forecastDiscussion?.text.contains("sea-breeze") == true)
    }

    @Test func nwsThrowsWithoutUserAgent() async throws {
        let client = NWSClient(userAgent: "", http: MockHTTPClient())
        await #expect(throws: ProviderError.self) {
            _ = try await client.alerts(at: Coordinate(latitude: 28.8, longitude: -81.27))
        }
    }
}
