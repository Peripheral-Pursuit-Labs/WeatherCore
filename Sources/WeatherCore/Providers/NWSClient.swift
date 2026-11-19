import Foundation
import OSLog

public struct NWSClient: Sendable {
    private let http: any HTTPClient
    private let cache: ResponseCache?
    private let userAgent: String
    private let baseURL = URL(string: "https://api.weather.gov")!

    /// User-Agent string identifying this app to NWS, with contact email.
    /// Required by NWS terms — e.g. "LunarDefense/1.0 (ben@ferrousguy.dev)"
    public init(
        userAgent: String,
        http: any HTTPClient = URLSessionHTTPClient(),
        cache: ResponseCache? = nil
    ) {
        self.userAgent = userAgent
        self.http = http
        self.cache = cache
    }

    public func alerts(at coord: Coordinate) async throws -> ProviderForecast {
        let log = WeatherLog.nws

        guard !userAgent.isEmpty else {
            log.error("Missing User-Agent string")
            throw ProviderError.missingAPIKey(.nws)
        }

        let url = baseURL.appendingPathComponent("alerts/active")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw ProviderError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "point", value: "\(coord.latitude),\(coord.longitude)")
        ]
        guard let finalURL = components.url else { throw ProviderError.invalidURL }

        let cacheKey = "nws:alerts:\(coord.latitude),\(coord.longitude)"
        let data: Data
        if let cached = await cache?.get(cacheKey) {
            log.debug("Cache hit")
            data = cached
        } else {
            log.debug("Fetching \(finalURL.absoluteString, privacy: .public)")
            var request = URLRequest(url: finalURL, timeoutInterval: 15)
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
            let (responseData, httpResponse) = try await self.http.data(for: request)
            guard (200..<300).contains(httpResponse.statusCode) else {
                log.error("HTTP \(httpResponse.statusCode)")
                throw ProviderError.http(status: httpResponse.statusCode, body: String(data: responseData, encoding: .utf8))
            }
            data = responseData
            await cache?.set(cacheKey, data: data, ttl: 180)
        }

        let decoded: NWSAlertsResponse
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            decoded = try decoder.decode(NWSAlertsResponse.self, from: data)
        } catch {
            log.error("Decode failed: \(error.localizedDescription, privacy: .public)")
            throw ProviderError.decoding(message: error.localizedDescription)
        }

        let alerts = decoded.features.map { feature in
            WeatherAlert(
                id: feature.id,
                event: feature.properties.event,
                headline: feature.properties.headline,
                description: feature.properties.description,
                instruction: feature.properties.instruction,
                severity: mapSeverity(feature.properties.severity),
                urgency: mapUrgency(feature.properties.urgency),
                certainty: mapCertainty(feature.properties.certainty),
                onset: feature.properties.onset,
                expires: feature.properties.expires,
                sender: feature.properties.senderName
            )
        }

        let discussion = try? await forecastDiscussion(at: coord)
        return ProviderForecast(
            provider: .nws,
            fetchedAt: Date(),
            current: nil,
            minutely: nil,
            hourly: nil,
            daily: nil,
            extras: .nws(NWSExtras(
                alerts: alerts,
                gridpointOffice: discussion?.office,
                forecastDiscussion: discussion
            ))
        )
    }

    private func forecastDiscussion(at coord: Coordinate) async throws -> NWSForecastDiscussion? {
        let pointURL = baseURL.appendingPathComponent("points/\(coord.latitude),\(coord.longitude)")
        let pointData = try await fetchData(
            from: pointURL,
            cacheKey: "nws:point:\(coord.latitude),\(coord.longitude)",
            ttl: 24 * 60 * 60
        )
        let point = try JSONDecoder().decode(NWSPointResponse.self, from: pointData)
        guard let office = point.properties.gridId, !office.isEmpty else { return nil }

        let listURL = baseURL.appendingPathComponent("products/types/AFD/locations/\(office)")
        let listData = try await fetchData(
            from: listURL,
            cacheKey: "nws:afd-list:\(office)",
            ttl: 30 * 60
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let products = try decoder.decode(NWSProductListResponse.self, from: listData)
        guard let latest = products.products.max(by: {
            ($0.issuanceTime ?? .distantPast) < ($1.issuanceTime ?? .distantPast)
        }) else { return nil }

        let productURL = baseURL.appendingPathComponent("products/\(latest.id)")
        let productData = try await fetchData(
            from: productURL,
            cacheKey: "nws:afd:\(latest.id)",
            ttl: 6 * 60 * 60
        )
        let product = try decoder.decode(NWSProductResponse.self, from: productData)
        guard let text = product.productText, !text.isEmpty else { return nil }
        return NWSForecastDiscussion(
            id: latest.id,
            office: office,
            issuedAt: product.issuanceTime ?? latest.issuanceTime,
            text: text
        )
    }

    private func fetchData(from url: URL, cacheKey: String, ttl: TimeInterval) async throws -> Data {
        if let cached = await cache?.get(cacheKey) { return cached }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await http.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw ProviderError.http(status: response.statusCode, body: String(data: data, encoding: .utf8))
        }
        await cache?.set(cacheKey, data: data, ttl: ttl)
        return data
    }

    private func mapSeverity(_ raw: String?) -> WeatherAlert.Severity {
        switch raw?.lowercased() {
        case "extreme": .extreme
        case "severe": .severe
        case "moderate": .moderate
        case "minor": .minor
        default: .unknown
        }
    }
    private func mapUrgency(_ raw: String?) -> WeatherAlert.Urgency {
        switch raw?.lowercased() {
        case "immediate": .immediate
        case "expected": .expected
        case "future": .future
        case "past": .past
        default: .unknown
        }
    }
    private func mapCertainty(_ raw: String?) -> WeatherAlert.Certainty {
        switch raw?.lowercased() {
        case "observed": .observed
        case "likely": .likely
        case "possible": .possible
        case "unlikely": .unlikely
        default: .unknown
        }
    }
}

private struct NWSPointResponse: Decodable {
    let properties: Properties

    struct Properties: Decodable {
        let gridId: String?
    }
}

private struct NWSProductListResponse: Decodable {
    let products: [Product]

    enum CodingKeys: String, CodingKey {
        case products = "@graph"
    }

    struct Product: Decodable {
        let id: String
        let issuanceTime: Date?
    }
}

private struct NWSProductResponse: Decodable {
    let issuanceTime: Date?
    let productText: String?
}

private struct NWSAlertsResponse: Decodable {
    let features: [Feature]
    struct Feature: Decodable {
        let id: String
        let properties: Properties
        struct Properties: Decodable {
            let event: String
            let headline: String?
            let description: String?
            let instruction: String?
            let severity: String?
            let urgency: String?
            let certainty: String?
            let onset: Date?
            let expires: Date?
            let senderName: String?
        }
    }
}
