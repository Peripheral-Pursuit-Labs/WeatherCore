import Foundation
import OSLog

/// Computes a DisagreementReport across provider forecasts for a given horizon.
/// Aligns timestamps to fixed windows (15-min for nextHour, 1-hour for hourly, 24-hour for daily)
/// and reports per-window probability spread plus an overall qualitative level.
public struct DisagreementAnalyzer: Sendable {

    public init() {}

    public func analyze(
        forecasts: [ProviderID: ProviderForecast],
        horizon: ForecastHorizon,
        referenceTime: Date = Date()
    ) -> DisagreementReport {
        let log = WeatherLog.analysis

        guard forecasts.count >= 2 else {
            log.debug("Skipping disagreement analysis: <2 providers (\(forecasts.count))")
            return .empty
        }

        let providersConsidered = Array(forecasts.keys).sorted { $0.rawValue < $1.rawValue }

        switch horizon {
        case .nextHour:
            return analyzeMinutely(forecasts: forecasts, referenceTime: referenceTime, providersConsidered: providersConsidered)
        case .hourly:
            return analyzeHourly(forecasts: forecasts, referenceTime: referenceTime, providersConsidered: providersConsidered)
        case .daily:
            return analyzeDaily(forecasts: forecasts, referenceTime: referenceTime, providersConsidered: providersConsidered)
        }
    }

    // MARK: - Per-horizon analysis

    private func analyzeMinutely(
        forecasts: [ProviderID: ProviderForecast],
        referenceTime: Date,
        providersConsidered: [ProviderID]
    ) -> DisagreementReport {
        // Build 15-minute windows for the next 60 minutes
        let windowStart = floorTo15Minutes(referenceTime)
        let windows = (0..<4).map { i -> DateInterval in
            let start = windowStart.addingTimeInterval(TimeInterval(i * 15 * 60))
            return DateInterval(start: start, duration: 15 * 60)
        }

        var windowReports: [DisagreementReport.WindowDisagreement] = []
        var consensus: [DateInterval: Double] = [:]

        for window in windows {
            var probs: [ProviderID: Double] = [:]
            var intensities: [ProviderID: Double] = [:]

            for (providerID, forecast) in forecasts {
                guard let minutely = forecast.minutely else { continue }
                let inWindow = minutely.points.filter { window.contains($0.time) }
                guard !inWindow.isEmpty else { continue }

                let avgProb = inWindow.compactMap(\.probability).reduce(0, +) / Double(max(inWindow.count, 1))
                let avgIntensity = inWindow.compactMap { $0.intensity?.converted(to: .millimetersPerHour).value }.reduce(0, +) / Double(max(inWindow.count, 1))

                probs[providerID] = avgProb
                intensities[providerID] = avgIntensity
            }

            let spread = (probs.values.max() ?? 0) - (probs.values.min() ?? 0)
            let level = classifyLevel(probabilitySpread: spread, intensities: intensities)
            consensus[window] = median(of: Array(probs.values))

            windowReports.append(DisagreementReport.WindowDisagreement(
                window: window,
                probabilityByProvider: probs,
                intensityByProvider: intensities,
                probabilitySpread: spread,
                level: level
            ))
        }

        return DisagreementReport(
            overallLevel: overallLevel(from: windowReports),
            windows: windowReports,
            consensus: consensus,
            providersConsidered: providersConsidered
        )
    }

    private func analyzeHourly(
        forecasts: [ProviderID: ProviderForecast],
        referenceTime: Date,
        providersConsidered: [ProviderID]
    ) -> DisagreementReport {
        let windowStart = floorToHour(referenceTime)
        let windows = (0..<24).map { i -> DateInterval in
            let start = windowStart.addingTimeInterval(TimeInterval(i * 3600))
            return DateInterval(start: start, duration: 3600)
        }

        var windowReports: [DisagreementReport.WindowDisagreement] = []
        var consensus: [DateInterval: Double] = [:]

        for window in windows {
            var probs: [ProviderID: Double] = [:]
            var intensities: [ProviderID: Double] = [:]

            for (providerID, forecast) in forecasts {
                guard let snapshot = forecast.hourly?.snapshots.first(where: { window.contains($0.time) }) else { continue }
                if let p = snapshot.precipitationProbability { probs[providerID] = p }
                if let i = snapshot.precipitationIntensity?.converted(to: .millimetersPerHour).value {
                    intensities[providerID] = i
                }
            }

            guard !probs.isEmpty else { continue }

            let spread = (probs.values.max() ?? 0) - (probs.values.min() ?? 0)
            let level = classifyLevel(probabilitySpread: spread, intensities: intensities)
            consensus[window] = median(of: Array(probs.values))

            windowReports.append(DisagreementReport.WindowDisagreement(
                window: window,
                probabilityByProvider: probs,
                intensityByProvider: intensities,
                probabilitySpread: spread,
                level: level
            ))
        }

        return DisagreementReport(
            overallLevel: overallLevel(from: windowReports),
            windows: windowReports,
            consensus: consensus,
            providersConsidered: providersConsidered
        )
    }

    private func analyzeDaily(
        forecasts: [ProviderID: ProviderForecast],
        referenceTime: Date,
        providersConsidered: [ProviderID]
    ) -> DisagreementReport {
        let dayStart = Calendar(identifier: .gregorian).startOfDay(for: referenceTime)
        let windows = (0..<7).map { i -> DateInterval in
            let start = dayStart.addingTimeInterval(TimeInterval(i * 86400))
            return DateInterval(start: start, duration: 86400)
        }

        var windowReports: [DisagreementReport.WindowDisagreement] = []
        var consensus: [DateInterval: Double] = [:]

        for window in windows {
            var probs: [ProviderID: Double] = [:]
            var accumulations: [ProviderID: Double] = [:]

            for (providerID, forecast) in forecasts {
                guard let day = forecast.daily?.days.first(where: { window.contains($0.date) }) else { continue }
                if let p = day.precipitationProbability { probs[providerID] = p }
                if let acc = day.precipitationAccumulation?.converted(to: .millimeters).value {
                    accumulations[providerID] = acc
                }
            }

            guard !probs.isEmpty else { continue }

            let spread = (probs.values.max() ?? 0) - (probs.values.min() ?? 0)
            let level = classifyLevel(probabilitySpread: spread, intensities: accumulations)
            consensus[window] = median(of: Array(probs.values))

            windowReports.append(DisagreementReport.WindowDisagreement(
                window: window,
                probabilityByProvider: probs,
                intensityByProvider: accumulations,
                probabilitySpread: spread,
                level: level
            ))
        }

        return DisagreementReport(
            overallLevel: overallLevel(from: windowReports),
            windows: windowReports,
            consensus: consensus,
            providersConsidered: providersConsidered
        )
    }

    // MARK: - Helpers

    private func classifyLevel(probabilitySpread spread: Double, intensities: [ProviderID: Double]) -> DisagreementReport.Level {
        // Qualitative disagreement: some providers say rain, some say dry
        let raining = intensities.values.filter { $0 > 0.1 }.count
        let dry = intensities.values.filter { $0 <= 0.1 }.count
        if raining > 0 && dry > 0 { return .high }

        switch spread {
        case ..<0.15: return .low
        case 0.15..<0.40: return .moderate
        default: return .high
        }
    }

    private func overallLevel(from windows: [DisagreementReport.WindowDisagreement]) -> DisagreementReport.Level {
        guard !windows.isEmpty else { return .none }
        if windows.contains(where: { $0.level == .high }) { return .high }
        if windows.contains(where: { $0.level == .moderate }) { return .moderate }
        return .low
    }

    private func floorTo15Minutes(_ date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let flooredMinute = (components.minute ?? 0) / 15 * 15
        var floored = components
        floored.minute = flooredMinute
        floored.second = 0
        return calendar.date(from: floored) ?? date
    }

    private func floorToHour(_ date: Date) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    private func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        return n % 2 == 0 ? (sorted[n/2 - 1] + sorted[n/2]) / 2 : sorted[n/2]
    }
}

private extension UnitSpeed {
    static let millimetersPerHour: UnitSpeed = UnitSpeed(
        symbol: "mm/h",
        converter: UnitConverterLinear(coefficient: 1.0 / 3_600_000.0) // mm/hr to m/s
    )
}
