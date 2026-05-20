import Foundation
import OSLog

public struct RainViewerClient: Sendable {
    private let http: any HTTPClient
    private let cache: ResponseCache?
    private let endpoint = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!

    public init(http: any HTTPClient = URLSessionHTTPClient(), cache: ResponseCache? = nil) {
        self.http = http
        self.cache = cache
    }

    /// Fetches current radar frames and nowcast (future) frames. No coordinate needed;
    /// RainViewer returns globally tiled data — consumer renders tiles in their map view.
    public func frames(near coord: Coordinate) async throws -> ProviderForecast {
        let log = WeatherLog.rainViewer
        let cacheKey = "rainviewer:frames"
        let data: Data
        if let cached = await cache?.get(cacheKey) {
            log.debug("Cache hit")
            data = cached
        } else {
            log.debug("Fetching weather-maps.json")
            let request = URLRequest(url: endpoint, timeoutInterval: 10)
            let (responseData, http) = try await self.http.data(for: request)
            guard (200..<300).contains(http.statusCode) else {
                log.error("HTTP \(http.statusCode)")
                throw ProviderError.http(status: http.statusCode, body: String(data: responseData, encoding: .utf8))
            }
            data = responseData
            // Short TTL — radar updates every 10 min
            await cache?.set(cacheKey, data: data, ttl: 120)
        }

        let decoded: RainViewerResponse
        do {
            decoded = try JSONDecoder().decode(RainViewerResponse.self, from: data)
        } catch {
            throw ProviderError.decoding(message: error.localizedDescription)
        }

        let pastFrames = (decoded.radar?.past ?? []).map { f in
            RadarFrame(id: f.path, time: Date(timeIntervalSince1970: TimeInterval(f.time)), path: f.path, isNowcast: false)
        }
        let nowcastFrames = (decoded.radar?.nowcast ?? []).map { f in
            RadarFrame(id: f.path, time: Date(timeIntervalSince1970: TimeInterval(f.time)), path: f.path, isNowcast: true)
        }

        let extras = RainViewerExtras(
            radarFrames: pastFrames,
            nowcastFrames: nowcastFrames,
            host: decoded.host
        )

        return ProviderForecast(
            provider: .rainViewer,
            fetchedAt: Date(),
            current: nil,
            minutely: nil,
            hourly: nil,
            daily: nil,
            extras: .rainViewer(extras)
        )
    }

    /// Construct a tile URL for a frame at the requested zoom and tile coordinate.
    /// Tile size 256 or 512, colorScheme 0-8 per RainViewer docs, smooth=true gives nicer output.
    public static func tileURL(
        host: String,
        framePath: String,
        zoom: Int,
        x: Int,
        y: Int,
        size: Int = 256,
        colorScheme: Int = 2,
        smooth: Bool = true,
        snow: Bool = false
    ) -> URL? {
        let smoothFlag = smooth ? 1 : 0
        let snowFlag = snow ? 1 : 0
        return URL(string: "\(host)\(framePath)/\(size)/\(zoom)/\(x)/\(y)/\(colorScheme)/\(smoothFlag)_\(snowFlag).png")
    }
}

private struct RainViewerResponse: Decodable {
    let version: String
    let generated: Int
    let host: String
    let radar: Radar?

    struct Radar: Decodable {
        let past: [Frame]?
        let nowcast: [Frame]?
        struct Frame: Decodable {
            let time: Int
            let path: String
        }
    }
}
