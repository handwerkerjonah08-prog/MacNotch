import XCTest
@testable import NotchCore

final class ModelsTests: XCTestCase {
    func testDefaultSettingsHaveEveryWidgetEnabledInOrder() {
        let settings = AppSettings.default
        XCTAssertEqual(settings.widgets.map(\.kind), WidgetKind.allCases)
        XCTAssertTrue(settings.widgets.allSatisfy(\.isEnabled))
        XCTAssertEqual(settings.enabledWidgetKinds, WidgetKind.allCases)
        XCTAssertEqual(settings.temperatureUnit, .fahrenheit)
        XCTAssertEqual(settings.weatherLocation, .glencoe)
        XCTAssertEqual(settings.islandMaterial, .liquidGlass)
        XCTAssertFalse(settings.shortcuts.isEmpty)
        XCTAssertEqual(settings.shortcuts.first?.name, "Discord")
    }

    func testSettingsRoundTripThroughJSON() throws {
        var settings = AppSettings.default
        settings.widgets = [
            WidgetConfig(kind: .weather, isEnabled: true),
            WidgetConfig(kind: .nowPlaying, isEnabled: false),
            WidgetConfig(kind: .fileShelf, isEnabled: true),
            WidgetConfig(kind: .webPages, isEnabled: false)
        ]
        settings.temperatureUnit = .celsius
        settings.expandTrigger = .click
        settings.glassTint = 0.2
        settings.shortcuts.append(WebShortcut(name: "Example", url: URL(string: "https://example.com")!))

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.enabledWidgetKinds, [.weather, .fileShelf])
    }

    func testDecodingToleratesMissingAndUnknownValues() throws {
        let json = """
        {
          "widgets": [
            {"kind": "weather", "isEnabled": false},
            {"kind": "hologram", "isEnabled": true},
            {"kind": "weather", "isEnabled": true}
          ],
          "temperatureUnit": "kelvin",
          "glassTint": 7
        }
        """
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        // Unknown kind dropped, duplicate dropped, missing kinds appended.
        XCTAssertEqual(decoded.widgets.first, WidgetConfig(kind: .weather, isEnabled: false))
        XCTAssertEqual(Set(decoded.widgets.map(\.kind)), Set(WidgetKind.allCases))
        XCTAssertEqual(decoded.widgets.count, WidgetKind.allCases.count)
        // Invalid enum falls back to the default.
        XCTAssertEqual(decoded.temperatureUnit, .fahrenheit)
        // Out of range slider value is clamped.
        XCTAssertEqual(decoded.glassTint, 1)
        // Missing values use defaults.
        XCTAssertEqual(decoded.shortcuts, AppSettings.default.shortcuts)
    }

    func testDecodingGarbageObjectFallsBackToDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, AppSettings.default)
    }

    func testPersistenceRoundTrip() throws {
        let suite = "MacNotchTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = CodableDefaults<AppSettings>(key: StorageKeys.settings, defaults: defaults)
        XCTAssertNil(store.load())

        var settings = AppSettings.default
        settings.hasCompletedOnboarding = true
        store.save(settings)
        XCTAssertEqual(store.load(), settings)

        store.clear()
        XCTAssertNil(store.load())
    }

    func testShortcutHostAndMonogram() {
        let shortcut = WebShortcut(name: "  discord", url: URL(string: "https://www.Discord.com/app")!)
        XCTAssertEqual(shortcut.host, "discord.com")
        XCTAssertEqual(shortcut.monogram, "D")
    }

    func testAllPresetsHaveValidURLs() {
        for preset in WebShortcutPreset.all {
            XCTAssertNotNil(preset.shortcut, preset.name)
            XCTAssertNotNil(URLNormalizer.normalize(preset.urlString), preset.name)
        }
    }

    func testWidgetMetadataIsComplete() {
        for kind in WidgetKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
            XCTAssertFalse(kind.subtitle.isEmpty)
            XCTAssertFalse(kind.symbolName.isEmpty)
        }
    }
}

final class URLNormalizerTests: XCTestCase {
    func testAddsHTTPSWhenMissing() {
        XCTAssertEqual(URLNormalizer.normalize("discord.com/app")?.absoluteString, "https://discord.com/app")
        XCTAssertEqual(URLNormalizer.normalize("  YouTube.com  ")?.absoluteString, "https://youtube.com")
    }

    func testKeepsExistingScheme() {
        XCTAssertEqual(URLNormalizer.normalize("http://example.com/a?b=1")?.absoluteString, "http://example.com/a?b=1")
        XCTAssertEqual(URLNormalizer.normalize("HTTPS://Example.com")?.absoluteString, "https://example.com")
    }

    func testRejectsInvalidInput() {
        XCTAssertNil(URLNormalizer.normalize(""))
        XCTAssertNil(URLNormalizer.normalize("   "))
        XCTAssertNil(URLNormalizer.normalize("not a url"))
        XCTAssertNil(URLNormalizer.normalize("discord"))
        XCTAssertNil(URLNormalizer.normalize("ftp://example.com"))
        XCTAssertNil(URLNormalizer.normalize("javascript:alert(1)"))
        XCTAssertNil(URLNormalizer.normalize("https://.com"))
        XCTAssertNil(URLNormalizer.normalize("https://exa..mple.com"))
    }

    func testAllowsLocalhost() {
        XCTAssertEqual(URLNormalizer.normalize("localhost:3000")?.absoluteString, "https://localhost:3000")
    }

    func testSuggestedNames() {
        func name(_ string: String) -> String { URLNormalizer.suggestedName(for: URL(string: string)!) }
        XCTAssertEqual(name("https://www.discord.com/app"), "Discord")
        XCTAssertEqual(name("https://www.youtube.com"), "YouTube")
        XCTAssertEqual(name("https://mail.google.com"), "Gmail")
        XCTAssertEqual(name("https://app.netlify.com"), "Netlify")
        XCTAssertEqual(name("https://www.bbc.co.uk/news"), "Bbc")
    }

    func testFaviconCandidatesOrder() {
        let candidates = URLNormalizer.faviconCandidates(for: URL(string: "https://www.discord.com/app")!)
        XCTAssertTrue(candidates[0].absoluteString.contains("domain=discord.com"))
        XCTAssertTrue(candidates[1].absoluteString.contains("duckduckgo.com/ip3/discord.com"))
        XCTAssertEqual(candidates.last?.absoluteString, "https://www.discord.com/apple-touch-icon.png")
        XCTAssertEqual(candidates.count, 3)
    }
}
