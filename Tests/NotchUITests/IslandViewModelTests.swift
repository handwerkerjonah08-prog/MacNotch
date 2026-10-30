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
        model.setFileDragNearby(true)
        XCTAssertEqual(model.presentation, .idle)

        let enabled = makeModel()
        enabled.setFileDragNearby(true)
        XCTAssertEqual(enabled.presentation, .expanded)
        enabled.setFileDragNearby(false)
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
        let inputs: [IslandInputs] = [
            IslandInputs(),
            IslandInputs(nowPlayingActive: true),
            IslandInputs(alert: .charging(level: 50)),
            IslandInputs(isPinnedOpen: true)
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
