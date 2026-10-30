import CoreGraphics
import XCTest
@testable import NotchCore

final class WidgetEditingTests: XCTestCase {
    func testRemovingAndAddingWidgets() {
        var settings = AppSettings.default
        settings.setWidget(.weather, enabled: false)
        XCTAssertEqual(settings.enabledWidgetKinds, [.nowPlaying, .webPages, .fileShelf])
        XCTAssertEqual(settings.disabledWidgetKinds, [.weather])

        // Adding back puts it at the end of the visible widgets.
        settings.setWidget(.weather, enabled: true)
        XCTAssertEqual(settings.enabledWidgetKinds, [.nowPlaying, .webPages, .fileShelf, .weather])
        XCTAssertTrue(settings.disabledWidgetKinds.isEmpty)
        XCTAssertEqual(settings.widgets.count, WidgetKind.allCases.count)
    }

    func testSettingSameStateIsNoOp() {
        var settings = AppSettings.default
        let before = settings.widgets
        settings.setWidget(.nowPlaying, enabled: true)
        XCTAssertEqual(settings.widgets, before)
    }

    func testMovingVisibleWidgets() {
        var settings = AppSettings.default
        settings.moveEnabledWidget(.fileShelf, toEnabledIndex: 0)
        XCTAssertEqual(settings.enabledWidgetKinds, [.fileShelf, .nowPlaying, .weather, .webPages])
        settings.moveEnabledWidget(.fileShelf, toEnabledIndex: 99)
        XCTAssertEqual(settings.enabledWidgetKinds, [.nowPlaying, .weather, .webPages, .fileShelf])
        settings.moveEnabledWidget(.weather, toEnabledIndex: -5)
        XCTAssertEqual(settings.enabledWidgetKinds.first, .weather)
    }

    func testMovingIgnoresHiddenWidgets() {
        var settings = AppSettings.default
        settings.setWidget(.nowPlaying, enabled: false)
        settings.moveEnabledWidget(.nowPlaying, toEnabledIndex: 0)
        XCTAssertFalse(settings.enabledWidgetKinds.contains(.nowPlaying))
        settings.moveEnabledWidget(.webPages, toEnabledIndex: 0)
        XCTAssertEqual(settings.enabledWidgetKinds, [.webPages, .weather, .fileShelf])
    }
}

final class ShortcutEditingTests: XCTestCase {
    private func url(_ string: String) -> URL { URL(string: string)! }

    func testAddShortcutDeduplicates() {
        var settings = AppSettings.default
        settings.shortcuts = []
        XCTAssertEqual(settings.addShortcut(for: url("https://www.figma.com/files"))?.name, "Figma")
        XCTAssertNil(settings.addShortcut(for: url("http://figma.com/files/")))
        XCTAssertNotNil(settings.addShortcut(for: url("https://figma.com/community")))
        XCTAssertEqual(settings.shortcuts.count, 2)
    }

    func testAddShortcutUsesGivenName() {
        var settings = AppSettings.default
        settings.shortcuts = []
        XCTAssertEqual(settings.addShortcut(for: url("https://example.com"), name: "  My Site ")?.name, "My Site")
        XCTAssertEqual(settings.addShortcut(for: url("https://other.com"), name: "   ")?.name, "Other")
    }

    func testDefaultShortcutsAreRecognized() {
        let settings = AppSettings.default
        XCTAssertTrue(settings.containsShortcut(for: url("https://discord.com/app/")))
        XCTAssertFalse(settings.containsShortcut(for: url("https://discord.com/channels")))
    }

    func testMoveAndRemoveShortcuts() {
        var settings = AppSettings.default
        let names = settings.shortcuts.map(\.name)
        let last = settings.shortcuts.last!
        settings.moveShortcut(id: last.id, to: 0)
        XCTAssertEqual(settings.shortcuts.first?.name, names.last)
        settings.moveShortcut(id: last.id, to: 100)
        XCTAssertEqual(settings.shortcuts.map(\.name), names)
        settings.removeShortcut(id: last.id)
        XCTAssertEqual(settings.shortcuts.count, names.count - 1)
        settings.moveShortcut(id: UUID(), to: 0)
        XCTAssertEqual(settings.shortcuts.count, names.count - 1)
    }
}

final class NotchInfoTests: XCTestCase {
    private let notch = CGSize(width: 190, height: 37)

    func testDefaultsShowNothingBesideTheNotch() {
        XCTAssertFalse(AppSettings.default.showsNotchInfo)
        XCTAssertEqual(AppSettings.default.notchLeading, NotchSlot.none)
    }

    func testSlotsRoundTripAndDecodeLeniently() throws {
        var settings = AppSettings.default
        settings.notchLeading = .weather
        settings.notchTrailing = .battery
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded.notchLeading, .weather)
        XCTAssertEqual(decoded.notchTrailing, .battery)
        XCTAssertTrue(decoded.showsNotchInfo)

        let odd = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"notchLeading":"stocks"}"#.utf8))
        XCTAssertEqual(odd.notchLeading, NotchSlot.none)
    }

    func testInfoShowsWhenNothingElseIsActive() {
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(showsInfo: true)), .compactInfo)
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(nowPlayingActive: true, showsInfo: true)), .compactNowPlaying)
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(alert: .charging(level: 5), showsInfo: true)), .alert(.charging(level: 5)))
    }

    func testEditingKeepsTheIslandOpen() {
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(trigger: .click, isEditing: true)), .expanded)
    }

    func testInfoWingsAreSymmetricAndFitTheirContent() {
        let both = IslandMetrics.size(for: .compactInfo, notch: notch, widgets: [], shortcutCount: 0, maxWidth: 1470, leading: .weather, trailing: .battery)
        let oneSide = IslandMetrics.size(for: .compactInfo, notch: notch, widgets: [], shortcutCount: 0, maxWidth: 1470, leading: .none, trailing: .battery)
        XCTAssertEqual(both, oneSide, "the wider slot sets both wings so the island stays centered")
        let small = IslandMetrics.size(for: .compactInfo, notch: notch, widgets: [], shortcutCount: 0, maxWidth: 1470, leading: .shelf, trailing: .none)
        XCTAssertLessThan(small.width, both.width)
        XCTAssertEqual(both.height, notch.height)
        for slot in NotchSlot.allCases where slot != .none {
            XCTAssertGreaterThan(IslandMetrics.infoWidth(for: slot), 0)
            XCTAssertFalse(slot.title.isEmpty)
        }
    }
}
