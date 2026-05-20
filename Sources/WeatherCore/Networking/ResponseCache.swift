import Foundation

/// Simple actor-isolated in-memory cache. No disk persistence — caller's job if they want it.
public actor ResponseCache {
    public struct Entry: Sendable {
        let data: Data
        let storedAt: Date
        let ttl: TimeInterval
        var isFresh: Bool { Date().timeIntervalSince(storedAt) < ttl }
    }

    private var storage: [String: Entry] = [:]
    private let defaultTTL: TimeInterval

    public init(defaultTTL: TimeInterval = 300) {
        self.defaultTTL = defaultTTL
    }

    public func get(_ key: String) -> Data? {
        guard let entry = storage[key], entry.isFresh else {
            if storage[key] != nil { storage.removeValue(forKey: key) }
            return nil
        }
        return entry.data
    }

    public func set(_ key: String, data: Data, ttl: TimeInterval? = nil) {
        storage[key] = Entry(data: data, storedAt: Date(), ttl: ttl ?? defaultTTL)
    }

    public func clear() { storage.removeAll() }
}
