import Testing
import Foundation
@testable import WeatherCore

@Suite("DisagreementAnalyzer aligns timestamps and quantifies disagreement")
struct DisagreementAnalyzerTests {

    let referenceTime: Date = {
        // Fixed Tuesday 2025-05-19 12:00 UTC for deterministic windowing
        var components = DateComponents()
        components.year = 2025
        components.month = 5
        components.day = 19
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }()

    @Test func returnsEmptyForFewerThanTwoProviders() {
        let analyzer = DisagreementAnalyzer()
        let result = analyzer.analyze(forecasts: [:], horizon: .nextHour, referenceTime: referenceTime)
        #expect(result.overallLevel == .none)
        #expect(result.windows.isEmpty)
    }

    @Test func detectsHighDisagreementWhenProvidersDisagreeOnPrecipOccurrence() {
        // Provider A says it's raining; provider B says it's dry. Highest disagreement.
        let providerA = makeForecast(provider: .pirateWeather, hourlyProb: 0.9, hourlyIntensity: 2.5)
        let providerB = makeForecast(provider: .openMeteo, hourlyProb: 0.1, hourlyIntensity: 0.0)

        let analyzer = DisagreementAnalyzer()
        let result = analyzer.analyze(
            forecasts: [.pirateWeather: providerA, .openMeteo: providerB],
            horizon: .hourly,
            referenceTime: referenceTime
        )

        #expect(result.overallLevel == .high)
        #expect(result.providersConsidered.count == 2)
    }

    @Test func detectsLowDisagreementWhenProvidersAgree() {
        let providerA = makeForecast(provider: .pirateWeather, hourlyProb: 0.6, hourlyIntensity: 1.0)
        let providerB = makeForecast(provider: .openMeteo, hourlyProb: 0.65, hourlyIntensity: 1.1)

        let analyzer = DisagreementAnalyzer()
        let result = analyzer.analyze(
            forecasts: [.pirateWeather: providerA, .openMeteo: providerB],
            horizon: .hourly,
            referenceTime: referenceTime
        )

        #expect(result.overallLevel == .low)
    }

    @Test func computesMedianConsensus() {
        let providerA = makeForecast(provider: .pirateWeather, hourlyProb: 0.3, hourlyIntensity: 0.5)
        let providerB = makeForecast(provider: .openMeteo, hourlyProb: 0.7, hourlyIntensity: 1.5)

        let analyzer = DisagreementAnalyzer()
        let result = analyzer.analyze(
            forecasts: [.pirateWeather: providerA, .openMeteo: providerB],
            horizon: .hourly,
            referenceTime: referenceTime
        )

        let consensusValues = Array(result.consensus.values)
        #expect(consensusValues.allSatisfy { $0 == 0.5 }, "Median of 0.3 and 0.7 should be 0.5")
    }

    @Test func minutelyAnalysisProducesFour15MinWindows() {
        let providerA = makeMinutelyForecast(provider: .pirateWeather, basedOn: referenceTime, probability: 0.5, intensity: 0.5)
        let providerB = makeMinutelyForecast(provider: .openMeteo, basedOn: referenceTime, probability: 0.55, intensity: 0.6)

        let analyzer = DisagreementAnalyzer()
        let result = analyzer.analyze(
            forecasts: [.pirateWeather: providerA, .openMeteo: providerB],
            horizon: .nextHour,
            referenceTime: referenceTime
        )

        #expect(result.windows.count == 4)
        #expect(result.windows.allSatisfy { $0.window.duration == 15 * 60 })
    }

    // MARK: - Builders

    private func makeForecast(
        provider: ProviderID,
        hourlyProb: Double,
        hourlyIntensity: Double
    ) -> ProviderForecast {
        let snapshots = (0..<24).map { i in
            WeatherSnapshot(
                time: referenceTime.addingTimeInterval(TimeInterval(i * 3600)),
                precipitationIntensity: Measurement(value: hourlyIntensity, unit: UnitSpeed.metersPerSecond),
                precipitationProbability: hourlyProb
            )
        }
        return ProviderForecast(
            provider: provider,
            fetchedAt: referenceTime,
            current: nil,
            minutely: nil,
            hourly: HourlyForecast(snapshots: snapshots),
            daily: nil,
            extras: .none
        )
    }

    private func makeMinutelyForecast(
        provider: ProviderID,
        basedOn reference: Date,
        probability: Double,
        intensity: Double
    ) -> ProviderForecast {
        let points = (0..<60).map { minute in
            MinutelyPoint(
                time: reference.addingTimeInterval(TimeInterval(minute * 60)),
                intensity: Measurement(value: intensity, unit: UnitSpeed.metersPerSecond),
                probability: probability
            )
        }
        return ProviderForecast(
            provider: provider,
            fetchedAt: reference,
            current: nil,
            minutely: MinutelyForecast(points: points),
            hourly: nil,
            daily: nil,
            extras: .none
        )
    }
}
