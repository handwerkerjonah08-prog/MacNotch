import Foundation

/// Stores Codable values as JSON in UserDefaults.
public struct CodableDefaults<Value: Codable> {
    public let key: String
    private let defaults: UserDefaults

    public init(key: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaults = defaults
    }

    public func load() -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    public func clear() {
        defaults.removeObject(forKey: key)
    }
}

public enum StorageKeys {
    public static let settings = "MacNotch.settings.v1"
    public static let shelf = "MacNotch.shelf.v1"
    public static let weatherCache = "MacNotch.weather.v1"
}
