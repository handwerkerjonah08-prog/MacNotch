import AppKit
import NotchCore
import SwiftUI
import XCTest
@testable import NotchUI

final class IslandViewModelTests: XCTestCase {
    @MainActor
    private func makeModel(_ settings: AppSettings = .default) -> IslandViewModel {
        IslandViewModel(
            settings: SettingsModel(preview: settings),
            music: MusicController(live: false),
            weather: WeatherService(live: false, location: .glencoe, unit: .fahrenheit),
            battery: BatteryMonitor(live: false),
            shelf: ShelfModel(live: false),
            favicons: FaviconCache(live: false),
            notch: NotchGeometry(notchRect: CGRect(x: 640, y: 919, width: 190, height: 37), hasHardwareNotch: true),
            maxWidth: 1454
        )
    }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @MainActor
    func testStartsIdleAndMatchesNotch() {
        let model = makeModel()
        XCTAssertEqual(model.presentation, .idle)
        XCTAssertEqual(model.islandSize.height, 37)
        XCTAssertEqual(model.islandSize.width, 190 + IslandMetrics.radii(for: .idle).top * 2)
    }

    @MainActor
    func testHoverExpandsThenCollapses() async {
        let model = makeModel()
        model.mouseInsideChanged(true)
        XCTAssertEqual(model.presentation, .idle, "Expansion waits a beat so passing the cursor by doesn't open it")
        await wait(0.3)
        XCTAssertEqual(model.presentation, .expanded)
        model.mouseInsideChanged(false)
        await wait(0.5)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testQuickPassDoesNotExpand() async {
        let model = makeModel()
        model.mouseInsideChanged(true)
        await wait(0.03)
        model.mouseInsideChanged(false)
        await wait(0.4)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testClickModeNeedsATap() async {
        var settings = AppSettings.default
        settings.expandTrigger = .click
        let model = makeModel(settings)
        model.mouseInsideChanged(true)
        await wait(0.3)
        XCTAssertEqual(model.presentation, .idle)
        model.islandTapped()
        XCTAssertEqual(model.presentation, .expanded)
        model.clickedOutside()
        model.mouseInsideChanged(false)
        await wait(0.6)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testPlayingMusicShowsCompactActivity() async {
        let model = makeModel()
        model.music.preview(track: TrackInfo(title: "Song", artist: "Artist", album: "", duration: 200), state: .playing, artwork: nil, elapsed: 0)
        await wait(0.05)
        XCTAssertEqual(model.presentation, .compactNowPlaying)
        XCTAssertGreaterThan(model.islandSize.width, model.size(for: .idle).width)

        model.music.preview(track: nil, state: .stopped, artwork: nil, elapsed: 0)
        await wait(0.05)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testNowPlayingActivityCanBeTurnedOff() async {
        let model = makeModel()
        model.settings.settings.showNowPlayingActivity = false
        model.music.preview(track: TrackInfo(title: "Song", artist: "", album: "", duration: 0), state: .playing, artwork: nil, elapsed: 0)
        await wait(0.05)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testAlertsDismissThemselves() async {
        let model = makeModel()
        model.showAlert(.shelfAdded(count: 2))
        XCTAssertEqual(model.presentation, .alert(.shelfAdded(count: 2)))
        await wait(AlertKind.shelfAdded(count: 2).duration + 0.4)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testFileDragsOnlyExpandWhenShelfIsOn() {
        var settings = AppSettings.default
        settings.widgets = settings.widgets.map { WidgetConfig(kind: $0.kind, isEnabled: $0.kind != .fileShelf) }
        let model = makeModel(settings)
        model.setDragNearby(.file)
        XCTAssertEqual(model.presentation, .idle)
        XCTAssertEqual(model.dragKind, .none)
        model.setDragNearby(.link)
        XCTAssertEqual(model.presentation, .expanded, "links still go to Web Pages")
        XCTAssertEqual(model.dragKind, .link)
        model.setDragNearby(.none)

        let enabled = makeModel()
        enabled.setDragNearby(.file)
        XCTAssertEqual(enabled.presentation, .expanded)
        XCTAssertEqual(enabled.dragKind, .file)
        enabled.setDragNearby(.none)
        XCTAssertEqual(enabled.presentation, .idle)
    }

    @MainActor
    func testExpandedSizeFollowsWidgetChoices() {
        let model = makeModel()
        model.islandTapped()
        let full = model.islandSize
        model.settings.settings.widgets = model.settings.settings.widgets.map {
            WidgetConfig(kind: $0.kind, isEnabled: $0.kind == .weather)
        }
        XCTAssertLessThan(model.islandSize.width, full.width)
        XCTAssertEqual(model.islandSize.height, full.height)
    }

    @MainActor
    func testCollapseAfterOpeningAShortcut() {
        let model = makeModel()
        model.islandTapped()
        XCTAssertEqual(model.presentation, .expanded)
        model.collapse()
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testShelfAddsAndRemovesFiles() throws {
        let shelf = ShelfModel(live: false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.txt")
        try "hi".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(shelf.add([file, file]), 1)
        XCTAssertEqual(shelf.items.count, 1)
        try FileManager.default.removeItem(at: file)
        shelf.pruneMissing()
        XCTAssertTrue(shelf.items.isEmpty)
    }

    @MainActor
    func testEveryPresentationRendersToAnImage() {
        let model = makeModel()
        model.music.preview(track: TrackInfo(title: "Entropy", artist: "Beach Bunny", album: "", duration: 221), state: .playing, artwork: nil, elapsed: 30)
        model.weather.preview(WeatherSnapshot(
            temperature: 54, apparentTemperature: nil, high: 61, low: 47, code: 2, isDay: true,
            humidity: nil, windSpeed: nil, unit: .fahrenheit, locationName: "Glencoe", fetchedAt: Date()
        ))
        model.settings.settings.notchLeading = .weather
        model.settings.settings.notchTrailing = .time
        let inputs: [IslandInputs] = [
            IslandInputs(),
            IslandInputs(nowPlayingActive: true),
            IslandInputs(alert: .charging(level: 50)),
            IslandInputs(alert: .shortcutAdded(name: "Figma")),
            IslandInputs(isPinnedOpen: true),
            IslandInputs(isEditing: true)
        ]
        for input in inputs {
            model.forceInputs(input)
            let renderer = ImageRenderer(content: SnapshotScene(model: model, canvas: CGSize(width: 1100, height: 260)).environment(\.forceGlassFallback, true)
                .environment(\.isSnapshotRendering, true))
            renderer.scale = 1
            let image = renderer.cgImage
            XCTAssertNotNil(image, "\(model.presentation)")
            XCTAssertEqual(image?.width, 1100)
        }
    }

    @MainActor
    func testNotchInfoShowsWhenChosen() {
        let model = makeModel()
        XCTAssertEqual(model.presentation, .idle)
        model.settings.settings.notchLeading = .weather
        XCTAssertEqual(model.presentation, .compactInfo)
        XCTAssertGreaterThan(model.islandSize.width, model.size(for: .idle).width)
        model.settings.settings.notchLeading = .none
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testEditModeRemovesAddsAndMovesWidgets() async {
        var settings = AppSettings.default
        settings.expandTrigger = .click
        let model = makeModel(settings)
        model.beginEditing()
        XCTAssertTrue(model.isEditing)
        XCTAssertEqual(model.presentation, .expanded)

        // Leaving the island doesn't close it while editing.
        model.mouseInsideChanged(true)
        model.mouseInsideChanged(false)
        await wait(0.6)
        XCTAssertEqual(model.presentation, .expanded)

        model.removeWidget(.weather)
        XCTAssertEqual(model.settings.settings.enabledWidgetKinds, [.nowPlaying, .webPages, .fileShelf])
        model.moveWidget(.fileShelf, toVisibleIndex: 0)
        XCTAssertEqual(model.settings.settings.enabledWidgetKinds, [.fileShelf, .nowPlaying, .webPages])
        model.addWidget(.weather)
        XCTAssertEqual(model.settings.settings.enabledWidgetKinds.last, .weather)

        let first = model.settings.settings.shortcuts[0]
        model.moveShortcut(first.id, to: 2)
        XCTAssertEqual(model.settings.settings.shortcuts[2].id, first.id)
        model.removeShortcut(first.id)
        XCTAssertFalse(model.settings.settings.shortcuts.contains { $0.id == first.id })

        model.clickedOutside()
        XCTAssertFalse(model.isEditing)
        XCTAssertEqual(model.presentation, .idle)
    }

    @MainActor
    func testDroppedLinkBecomesAWebPage() async throws {
        let model = makeModel()
        let before = model.settings.settings.shortcuts.count
        let provider = NSItemProvider(object: NSURL(string: "https://www.figma.com/files")!)
        XCTAssertTrue(model.handleDrop([provider]))
        await wait(0.5)
        XCTAssertEqual(model.settings.settings.shortcuts.count, before + 1)
        XCTAssertEqual(model.settings.settings.shortcuts.last?.name, "Figma")
        XCTAssertEqual(model.presentation, .alert(.shortcutAdded(name: "Figma")))

        // The same link again is ignored.
        XCTAssertTrue(model.handleDrop([NSItemProvider(object: NSURL(string: "https://figma.com/files/")!)]))
        await wait(0.5)
        XCTAssertEqual(model.settings.settings.shortcuts.count, before + 1)
    }

    func testDroppedURLsAreSortedIntoFilesAndLinks() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString).txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let providers = [
            NSItemProvider(object: file as NSURL),
            NSItemProvider(object: NSURL(string: "https://example.com/page")!),
            NSItemProvider(object: NSURL(string: "mailto:someone@example.com")!)
        ]
        let dropped = await ShelfModel.droppedURLs(from: providers)
        XCTAssertEqual(dropped.files.map(\.lastPathComponent), [file.lastPathComponent])
        XCTAssertEqual(dropped.links.map(\.absoluteString), ["https://example.com/page"])
    }

    func testDarkLogosAreInvertedButColorfulOnesAreNot() {
        func icon(_ color: NSColor, filled: Bool) -> NSImage {
            NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
                color.setFill()
                if filled {
                    rect.fill()
                } else {
                    NSBezierPath(ovalIn: rect.insetBy(dx: 10, dy: 10)).fill()
                }
                return true
            }
        }
        XCTAssertTrue(ImageColor.isDarkMonochromeGlyph(icon(.black, filled: false)))
        XCTAssertFalse(ImageColor.isDarkMonochromeGlyph(icon(.systemRed, filled: false)))
        XCTAssertFalse(ImageColor.isDarkMonochromeGlyph(icon(.black, filled: true)), "filled squares keep their look")
        XCTAssertFalse(ImageColor.isDarkMonochromeGlyph(icon(.white, filled: false)))
        XCTAssertTrue(ImageColor.hasTransparentBackground(icon(.systemBlue, filled: false)))
        XCTAssertFalse(ImageColor.hasTransparentBackground(icon(.systemBlue, filled: true)))
    }

    func testTilesAreRemovedFromBehindLogos() throws {
        func tile(_ background: NSColor, logo: NSColor) -> NSImage {
            NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
                background.setFill()
                NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20).fill()
                logo.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 36, dy: 36)).fill()
                return true
            }
        }
        // Orange tile, white logo: the tile goes and the logo turns orange.
        let orange = try XCTUnwrap(ImageColor.removingBackground(tile(.systemOrange, logo: .white)))
        XCTAssertTrue(ImageColor.hasTransparentBackground(orange))
        XCTAssertFalse(ImageColor.isDarkMonochromeGlyph(orange))
        XCTAssertEqual(SiteIcon(image: tile(.systemOrange, logo: .white)).invertsOnDark, false)

        // Black tile, white logo (Roblox style): a white logo remains.
        let black = try XCTUnwrap(ImageColor.removingBackground(tile(.black, logo: .white)))
        XCTAssertTrue(ImageColor.hasTransparentBackground(black))
        XCTAssertFalse(SiteIcon(image: tile(.black, logo: .white)).invertsOnDark)

        // White tile, black logo: the black logo is inverted to show on dark glass.
        XCTAssertTrue(SiteIcon(image: tile(.white, logo: .black)).invertsOnDark)

        // Already transparent logos and busy pictures are left alone.
        let transparent = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        XCTAssertNil(ImageColor.removingBackground(transparent))
        let busy = NSImage(size: NSSize(width: 64, height: 64), flipped: false) { rect in
            NSGradient(colors: [.systemRed, .systemGreen, .systemBlue])?.draw(in: rect, angle: 30)
            return true
        }
        XCTAssertNil(ImageColor.removingBackground(busy))
    }

    func testDistributedObserverReceivesBroadcasts() {
        let expectation = expectation(description: "notification")
        let name = "app.macnotch.tests.\(UUID().uuidString)"
        let observer = DistributedObserver(name: name) { info in
            if info["Player State"] as? String == "Playing" {
                expectation.fulfill()
            }
        }
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(name), object: nil, userInfo: ["Player State": "Playing"], deliverImmediately: true
        )
        wait(for: [expectation], timeout: 5)
        withExtendedLifetime(observer) {}
    }

    func testBatteryReadDoesNotCrash() {
        // CI Macs have no battery, so nil is fine; a laptop returns a level between 0 and 100.
        if let snapshot = BatteryMonitor.read() {
            XCTAssertTrue((0...100).contains(snapshot.level))
        }
    }

    func testLiveWeatherAndGeocoding() async throws {
        do {
            let locations = try await WeatherService.searchLocations("Glencoe")
            XCTAssertTrue(locations.contains { $0.region == "Illinois" }, "\(locations)")
            let url = OpenMeteo.forecastURL(for: .glencoe, unit: .fahrenheit)
            let (data, _) = try await URLSession.shared.data(from: url)
            let snapshot = try OpenMeteo.decodeForecast(data, unit: .fahrenheit, locationName: "Glencoe")
            XCTAssertTrue((-60...130).contains(snapshot.temperature))
        } catch let error as URLError {
            throw XCTSkip("Network unavailable: \(error.localizedDescription)")
        }
    }
}
