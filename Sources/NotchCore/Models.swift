import Foundation

// MARK: - Widgets

public enum WidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case nowPlaying
    case weather
    case webPages
    case fileShelf

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nowPlaying: return "Now Playing"
        case .weather: return "Weather"
        case .webPages: return "Web Pages"
        case .fileShelf: return "File Shelf"
        }
    }

    public var subtitle: String {
        switch self {
        case .nowPlaying: return "Apple Music artwork, progress and controls"
        case .weather: return "Current conditions with today's high and low"
        case .webPages: return "Your saved sites, one click to open"
        case .fileShelf: return "Drop files on the notch, drag them out later"
        }
    }

    public var symbolName: String {
        switch self {
        case .nowPlaying: return "music.note"
        case .weather: return "cloud.sun.fill"
        case .webPages: return "globe"
        case .fileShelf: return "tray.full.fill"
        }
    }
}

public struct WidgetConfig: Codable, Equatable, Identifiable, Sendable {
    public var kind: WidgetKind
    public var isEnabled: Bool

    public var id: WidgetKind { kind }

    public init(kind: WidgetKind, isEnabled: Bool) {
        self.kind = kind
        self.isEnabled = isEnabled
    }
}

// MARK: - Web shortcuts

public struct WebShortcut: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var url: URL

    public init(id: UUID = UUID(), name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }

    public var host: String {
        let host = url.host?.lowercased() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public var monogram: String {
        let letter = name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? host.first ?? "?"
        return String(letter).uppercased()
    }
}

public struct WebShortcutPreset: Equatable, Identifiable, Sendable {
    public let name: String
    public let urlString: String
    public var id: String { urlString }

    public var shortcut: WebShortcut? {
        guard let url = URL(string: urlString) else { return nil }
        return WebShortcut(name: name, url: url)
    }

    public static let all: [WebShortcutPreset] = [
        .init(name: "Discord", urlString: "https://discord.com/app"),
        .init(name: "YouTube", urlString: "https://www.youtube.com"),
        .init(name: "Gmail", urlString: "https://mail.google.com"),
        .init(name: "Claude", urlString: "https://claude.ai"),
        .init(name: "ChatGPT", urlString: "https://chatgpt.com"),
        .init(name: "Roblox Creator Hub", urlString: "https://create.roblox.com/dashboard/creations"),
        .init(name: "GitHub", urlString: "https://github.com"),
        .init(name: "Calendar", urlString: "https://calendar.google.com"),
        .init(name: "Notion", urlString: "https://www.notion.so"),
        .init(name: "Figma", urlString: "https://www.figma.com"),
        .init(name: "Reddit", urlString: "https://www.reddit.com"),
        .init(name: "X", urlString: "https://x.com"),
        .init(name: "Netflix", urlString: "https://www.netflix.com"),
        .init(name: "Spotify", urlString: "https://open.spotify.com")
    ]
}

// MARK: - Weather location

public struct WeatherLocation: Codable, Hashable, Sendable {
    public var name: String
    public var region: String
    public var latitude: Double
    public var longitude: Double

    public init(name: String, region: String, latitude: Double, longitude: Double) {
        self.name = name
        self.region = region
        self.latitude = latitude
        self.longitude = longitude
    }

    public var displayName: String {
        region.isEmpty ? name : "\(name), \(region)"
    }

    public static let glencoe = WeatherLocation(
        name: "Glencoe", region: "Illinois", latitude: 42.1350, longitude: -87.7581
    )
}

// MARK: - Preferences

public enum TemperatureUnit: String, Codable, CaseIterable, Identifiable, Sendable {
    case fahrenheit
    case celsius

    public var id: String { rawValue }
    public var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    public var apiValue: String { rawValue }
}

public enum ExpandTrigger: String, Codable, CaseIterable, Identifiable, Sendable {
    case hover
    case click

    public var id: String { rawValue }
    public var title: String { self == .hover ? "Hover" : "Click" }
}

public enum IslandMaterial: String, Codable, CaseIterable, Identifiable, Sendable {
    case liquidGlass
    case black

    public var id: String { rawValue }
    public var title: String { self == .liquidGlass ? "Liquid Glass" : "Classic Black" }
}

// MARK: - App settings

public struct AppSettings: Codable, Equatable, Sendable {
    public var widgets: [WidgetConfig]
    public var shortcuts: [WebShortcut]
    public var weatherLocation: WeatherLocation
    public var temperatureUnit: TemperatureUnit
    public var expandTrigger: ExpandTrigger
    public var islandMaterial: IslandMaterial
    /// 0 = ultra clear glass, 1 = fully tinted. Mirrors the iOS 27 Liquid Glass slider.
    public var glassTint: Double
    public var hapticsEnabled: Bool
    public var showMenuBarIcon: Bool
    public var showNowPlayingActivity: Bool
    public var chargingAlerts: Bool
    public var lowBatteryAlerts: Bool
    public var hasCompletedOnboarding: Bool

    public init(
        widgets: [WidgetConfig],
        shortcuts: [WebShortcut],
        weatherLocation: WeatherLocation,
        temperatureUnit: TemperatureUnit,
        expandTrigger: ExpandTrigger,
        islandMaterial: IslandMaterial,
        glassTint: Double,
        hapticsEnabled: Bool,
        showMenuBarIcon: Bool,
        showNowPlayingActivity: Bool,
        chargingAlerts: Bool,
        lowBatteryAlerts: Bool,
        hasCompletedOnboarding: Bool
    ) {
        self.widgets = AppSettings.normalizedWidgets(widgets)
        self.shortcuts = shortcuts
        self.weatherLocation = weatherLocation
        self.temperatureUnit = temperatureUnit
        self.expandTrigger = expandTrigger
        self.islandMaterial = islandMaterial
        self.glassTint = min(max(glassTint, 0), 1)
        self.hapticsEnabled = hapticsEnabled
        self.showMenuBarIcon = showMenuBarIcon
        self.showNowPlayingActivity = showNowPlayingActivity
        self.chargingAlerts = chargingAlerts
        self.lowBatteryAlerts = lowBatteryAlerts
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }

    public static let defaultWidgets: [WidgetConfig] = WidgetKind.allCases.map {
        WidgetConfig(kind: $0, isEnabled: true)
    }

    public static let defaultShortcuts: [WebShortcut] = ["Discord", "YouTube", "Roblox Creator Hub", "Claude"]
        .compactMap { name in WebShortcutPreset.all.first { $0.name == name }?.shortcut }

    public static let `default` = AppSettings(
        widgets: defaultWidgets,
        shortcuts: defaultShortcuts,
        weatherLocation: .glencoe,
        temperatureUnit: .fahrenheit,
        expandTrigger: .hover,
        islandMaterial: .liquidGlass,
        glassTint: 0.55,
        hapticsEnabled: true,
        showMenuBarIcon: true,
        showNowPlayingActivity: true,
        chargingAlerts: true,
        lowBatteryAlerts: true,
        hasCompletedOnboarding: false
    )

    /// Enabled widget kinds, in display order.
    public var enabledWidgetKinds: [WidgetKind] {
        widgets.filter(\.isEnabled).map(\.kind)
    }

    public func isEnabled(_ kind: WidgetKind) -> Bool {
        widgets.first { $0.kind == kind }?.isEnabled ?? false
    }

    /// Keeps the user's order, drops duplicates and appends any kinds a newer version added.
    public static func normalizedWidgets(_ widgets: [WidgetConfig]) -> [WidgetConfig] {
        var seen = Set<WidgetKind>()
        var result: [WidgetConfig] = []
        for widget in widgets where !seen.contains(widget.kind) {
            seen.insert(widget.kind)
            result.append(widget)
        }
        for kind in WidgetKind.allCases where !seen.contains(kind) {
            result.append(WidgetConfig(kind: kind, isEnabled: true))
        }
        return result
    }

    // MARK: Lenient decoding so an older or partially corrupt file never wipes everything.

    private enum CodingKeys: String, CodingKey {
        case widgets, shortcuts, weatherLocation, temperatureUnit, expandTrigger, islandMaterial
        case glassTint, hapticsEnabled, showMenuBarIcon, showNowPlayingActivity
        case chargingAlerts, lowBatteryAlerts, hasCompletedOnboarding
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.default

        let widgetList = (try? c.decodeIfPresent([Lenient<WidgetConfig>].self, forKey: .widgets))?
            .compactMap(\.value)
        let shortcutList = (try? c.decodeIfPresent([Lenient<WebShortcut>].self, forKey: .shortcuts))?
            .compactMap(\.value)

        self.init(
            widgets: widgetList ?? d.widgets,
            shortcuts: shortcutList ?? d.shortcuts,
            weatherLocation: (try? c.decodeIfPresent(WeatherLocation.self, forKey: .weatherLocation)) ?? d.weatherLocation,
            temperatureUnit: (try? c.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit)) ?? d.temperatureUnit,
            expandTrigger: (try? c.decodeIfPresent(ExpandTrigger.self, forKey: .expandTrigger)) ?? d.expandTrigger,
            islandMaterial: (try? c.decodeIfPresent(IslandMaterial.self, forKey: .islandMaterial)) ?? d.islandMaterial,
            glassTint: (try? c.decodeIfPresent(Double.self, forKey: .glassTint)) ?? d.glassTint,
            hapticsEnabled: (try? c.decodeIfPresent(Bool.self, forKey: .hapticsEnabled)) ?? d.hapticsEnabled,
            showMenuBarIcon: (try? c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon)) ?? d.showMenuBarIcon,
            showNowPlayingActivity: (try? c.decodeIfPresent(Bool.self, forKey: .showNowPlayingActivity)) ?? d.showNowPlayingActivity,
            chargingAlerts: (try? c.decodeIfPresent(Bool.self, forKey: .chargingAlerts)) ?? d.chargingAlerts,
            lowBatteryAlerts: (try? c.decodeIfPresent(Bool.self, forKey: .lowBatteryAlerts)) ?? d.lowBatteryAlerts,
            hasCompletedOnboarding: (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)) ?? d.hasCompletedOnboarding
        )
    }
}

/// Decodes an element if possible, otherwise yields nil instead of failing the whole array.
struct Lenient<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
