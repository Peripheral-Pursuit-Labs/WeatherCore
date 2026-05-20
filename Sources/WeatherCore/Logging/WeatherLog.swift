import Foundation
import OSLog

/// Centralized OSLog access. Category strings double as filter terms in Console.app
/// and as breadcrumbs in log lines for post-hoc debugging.
public enum WeatherLog {
    public static let subsystem = "dev.ferrousguy.weathercore"

    public static let client          = Logger(subsystem: subsystem, category: "client")
    public static let pirate          = Logger(subsystem: subsystem, category: "provider.pirate")
    public static let openMeteo       = Logger(subsystem: subsystem, category: "provider.openmeteo")
    public static let rainViewer      = Logger(subsystem: subsystem, category: "provider.rainviewer")
    public static let nws             = Logger(subsystem: subsystem, category: "provider.nws")
    public static let networking      = Logger(subsystem: subsystem, category: "networking")
    public static let analysis        = Logger(subsystem: subsystem, category: "analysis")
    public static let cache           = Logger(subsystem: subsystem, category: "cache")

    public static func forProvider(_ id: ProviderID) -> Logger {
        switch id {
        case .pirateWeather: pirate
        case .openMeteo: openMeteo
        case .rainViewer: rainViewer
        case .nws: nws
        }
    }
}
