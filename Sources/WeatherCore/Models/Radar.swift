import Foundation

public struct RadarFrame: Sendable, Codable, Identifiable {
    public let id: String          // path-derived identifier from RainViewer
    public let time: Date
    public let path: String        // append to host + tile params client-side
    public let isNowcast: Bool

    public init(id: String, time: Date, path: String, isNowcast: Bool) {
        self.id = id
        self.time = time
        self.path = path
        self.isNowcast = isNowcast
    }
}

public struct WeatherAlert: Sendable, Codable, Identifiable {
    public enum Severity: String, Sendable, Codable {
        case extreme, severe, moderate, minor, unknown
    }
    public enum Urgency: String, Sendable, Codable {
        case immediate, expected, future, past, unknown
    }
    public enum Certainty: String, Sendable, Codable {
        case observed, likely, possible, unlikely, unknown
    }

    public let id: String
    public let event: String       // "Severe Thunderstorm Warning"
    public let headline: String?
    public let description: String?
    public let instruction: String?
    public let severity: Severity
    public let urgency: Urgency
    public let certainty: Certainty
    public let onset: Date?
    public let expires: Date?
    public let sender: String?

    public init(
        id: String,
        event: String,
        headline: String?,
        description: String?,
        instruction: String?,
        severity: Severity,
        urgency: Urgency,
        certainty: Certainty,
        onset: Date?,
        expires: Date?,
        sender: String?
    ) {
        self.id = id
        self.event = event
        self.headline = headline
        self.description = description
        self.instruction = instruction
        self.severity = severity
        self.urgency = urgency
        self.certainty = certainty
        self.onset = onset
        self.expires = expires
        self.sender = sender
    }
}
