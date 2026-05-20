# WeatherCore

A UI-free Swift package for acquiring, normalizing, and analyzing weather data from multiple providers. Built for iOS 26+ with Swift 6 strict concurrency.

## Design

Five providers, one unified call:

- **Pirate Weather** — Dark Sky-shaped JSON, HRRR/NBM-backed, minute-by-minute precipitation
- **Open-Meteo** — multi-model queries (GFS HRRR, ECMWF, ICON, etc.), 15-minute precipitation granularity, no API key
- **WeatherKit** — Apple's native forecast (current/minute/hourly/daily). Requires the WeatherKit entitlement; no API key
- **RainViewer** — radar tiles and 30-minute nowcast frames
- **NWS** — active weather alerts (severe thunderstorm, flash flood warnings)

Each provider client is independently usable. The top-level `WeatherClient` orchestrates them concurrently, captures per-provider failures without throwing, and **automatically computes a disagreement report** when called with `unifiedForecast()`.

Disagreement is computed across the three providers that produce comparable point forecasts — **Pirate Weather, Open-Meteo, and WeatherKit**. RainViewer (radar) and NWS (alerts) carry no probability/intensity values to compare. With ≥2 of the forecast providers available, the analyzer aligns their timestamps and quantifies how much they disagree.

## Quick start

```swift
import WeatherCore

let client = WeatherClient(config: .init(
    pirateWeatherAPIKey: "your-key",
    nwsUserAgent: "MyApp/1.0 (you@example.com)",
    enableWeatherKit: true   // uses the host app's WeatherKit entitlement
))

let forecast = await client.unifiedForecast(
    at: Coordinate(latitude: 28.8, longitude: -81.27),
    horizon: .nextHour
)

// Per-provider normalized data
let pirate = forecast.perProvider[.pirateWeather]
let openMeteo = forecast.perProvider[.openMeteo]
let weatherKit = forecast.perProvider[.weatherKit]

// Provider-specific extras when you need them
if case .pirateWeather(let extras) = pirate?.extras {
    print("CAPE: \(extras.cape ?? 0) J/kg")  // >2500 implies thunderstorm
}

// Disagreement — auto-computed, ready for your UI
switch forecast.disagreement.overallLevel {
case .high:   // Models disagree about whether precip is occurring
case .moderate: // Type agreement, intensity disagreement
case .low:    // Models agree
case .none:   // <2 providers available
}

// Alerts
for alert in forecast.alerts where alert.severity == .severe {
    // surface in UI
}
```

## Architecture

```
WeatherCore/
├── Models/         # Sendable value types: Coordinate, WeatherSnapshot, etc.
├── Client/         # WeatherClient — fans out to providers concurrently
├── Providers/      # PirateWeather, OpenMeteo, WeatherKit, RainViewer, NWS clients
├── Networking/     # HTTPClient protocol + URLSession impl, ResponseCache actor
├── Analysis/       # DisagreementAnalyzer
└── Logging/        # OSLog facades, one Logger per component
```

## Testing

Tests use Swift Testing (`@Suite`, `@Test`, `#expect`). `MockHTTPClient` lets you stub responses by URL substring. WeatherKit is the native framework (not HTTP), so it's abstracted behind the `WeatherKitForecasting` protocol and stubbed directly — no entitlement needed in tests. Run with `swift test`.

## What's intentionally not in scope

- UI (Swift package is UI-free by design)
- Persistence (caller's responsibility; in-memory cache only)
- CoreLocation integration (caller supplies lat/lon)
- API key storage (caller passes keys via config)
- Map tile rendering (RainViewerClient returns tile URLs; consumer renders)
