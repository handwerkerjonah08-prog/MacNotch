import XCTest
@testable import NotchCore

final class NotchGeometryTests: XCTestCase {
    // 15" MacBook Air at the default "looks like 1470 x 956" scaling.
    private let airFrame = CGRect(x: 0, y: 0, width: 1470, height: 956)

    func testHardwareNotchIsMeasuredFromAuxiliaryAreas() {
        let geometry = NotchGeometry.compute(
            screenFrame: airFrame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 919),
            safeAreaTop: 37,
            auxiliaryLeftWidth: 640,
            auxiliaryRightWidth: 640
        )
        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 640, y: 919, width: 190, height: 37))
        XCTAssertEqual(geometry.notchRect.midX, airFrame.midX)
    }

    func testSecondaryScreenOffsetIsRespected() {
        let frame = CGRect(x: -1470, y: 200, width: 1470, height: 956)
        let geometry = NotchGeometry.compute(
            screenFrame: frame, visibleFrame: frame, safeAreaTop: 37,
            auxiliaryLeftWidth: 640, auxiliaryRightWidth: 640
        )
        XCTAssertEqual(geometry.notchRect.minX, -830)
        XCTAssertEqual(geometry.notchRect.maxY, frame.maxY)
    }

    func testFallbackOnDisplayWithoutNotch() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry.compute(
            screenFrame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            safeAreaTop: 0, auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil
        )
        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.size, CGSize(width: NotchGeometry.fallbackNotchWidth, height: 25))
        XCTAssertEqual(geometry.notchRect.midX, 960)
        XCTAssertEqual(geometry.notchRect.maxY, 1080)
    }

    func testFallbackWithHiddenMenuBar() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = NotchGeometry.compute(
            screenFrame: frame, visibleFrame: frame, safeAreaTop: 0,
            auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil
        )
        XCTAssertEqual(geometry.size.height, 32)
    }
}

final class IslandMetricsTests: XCTestCase {
    private let notch = CGSize(width: 190, height: 37)

    private func size(_ presentation: IslandPresentation, widgets: [WidgetKind] = WidgetKind.allCases, shortcuts: Int = 4) -> CGSize {
        IslandMetrics.size(for: presentation, notch: notch, widgets: widgets, shortcutCount: shortcuts, maxWidth: 1470)
    }

    func testIdleBodyMatchesNotchExactly() {
        let idle = size(.idle)
        let flare = IslandMetrics.radii(for: .idle).top * 2
        XCTAssertEqual(idle.width - flare, notch.width)
        XCTAssertEqual(idle.height, notch.height)
    }

    func testPresentationsGrowInTheExpectedOrder() {
        let idle = size(.idle)
        let compact = size(.compactNowPlaying)
        let alert = size(.alert(.charging(level: 80)))
        let expanded = size(.expanded)
        XCTAssertLessThan(idle.width, compact.width)
        XCTAssertLessThan(compact.width, alert.width)
        XCTAssertLessThan(alert.width, expanded.width)
        XCTAssertEqual(compact.height, notch.height)
        XCTAssertGreaterThan(expanded.height, notch.height + IslandMetrics.cardHeight)
    }

    func testExpandedWidthTracksEnabledWidgets() {
        let all = size(.expanded)
        let weatherOnly = size(.expanded, widgets: [.weather])
        let none = size(.expanded, widgets: [])
        XCTAssertGreaterThan(all.width, weatherOnly.width)
        // Header still needs room either side of the notch.
        let minimum = notch.width + IslandMetrics.minHeaderSideWidth * 2 + IslandMetrics.radii(for: .expanded).top * 2
        XCTAssertEqual(weatherOnly.width, minimum)
        XCTAssertEqual(none.width, minimum)
    }

    func testExpandedWidthIsCappedToScreen() {
        let capped = IslandMetrics.size(for: .expanded, notch: notch, widgets: WidgetKind.allCases, shortcutCount: 8, maxWidth: 600)
        XCTAssertEqual(capped.width, 600)
    }

    func testShortcutColumns() {
        XCTAssertEqual(IslandMetrics.shortcutColumns(for: 0), 2)
        XCTAssertEqual(IslandMetrics.shortcutColumns(for: 1), 2)
        XCTAssertEqual(IslandMetrics.shortcutColumns(for: 4), 2)
        XCTAssertEqual(IslandMetrics.shortcutColumns(for: 5), 3)
        XCTAssertEqual(IslandMetrics.shortcutColumns(for: 8), 4)
        XCTAssertEqual(IslandMetrics.shortcutColumns(for: 30), 4)
        XCTAssertGreaterThan(
            IslandMetrics.cardWidth(for: .webPages, shortcutCount: 6),
            IslandMetrics.cardWidth(for: .webPages, shortcutCount: 2)
        )
    }

    func testMaximumSizeCoversEveryPresentation() {
        let maximum = IslandMetrics.maximumSize(notch: notch, maxWidth: 1470)
        let presentations: [IslandPresentation] = [
            .idle, .compactNowPlaying, .expanded,
            .alert(.charging(level: 1)), .alert(.pluggedIn(level: 1)), .alert(.unplugged(level: 1)),
            .alert(.lowBattery(level: 1)), .alert(.shelfAdded(count: 1))
        ]
        for presentation in presentations {
            let s = size(presentation, shortcuts: 30)
            XCTAssertLessThanOrEqual(s.width, maximum.width, "\(presentation)")
            XCTAssertLessThanOrEqual(s.height, maximum.height, "\(presentation)")
        }
    }
}

final class IslandStateMachineTests: XCTestCase {
    func testIdleByDefault() {
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs()), .idle)
    }

    func testNowPlayingShowsCompact() {
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(nowPlayingActive: true)), .compactNowPlaying)
    }

    func testAlertBeatsNowPlaying() {
        let inputs = IslandInputs(nowPlayingActive: true, alert: .charging(level: 50))
        XCTAssertEqual(IslandStateMachine.presentation(for: inputs), .alert(.charging(level: 50)))
    }

    func testHoverExpandsOnlyInHoverMode() {
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(isHovering: true, trigger: .hover)), .expanded)
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(isHovering: true, trigger: .click)), .idle)
        XCTAssertEqual(
            IslandStateMachine.presentation(for: IslandInputs(isHovering: true, isPinnedOpen: true, trigger: .click)),
            .expanded
        )
    }

    func testDraggingAlwaysExpands() {
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(isFileDragNearby: true, trigger: .click)), .expanded)
        XCTAssertEqual(IslandStateMachine.presentation(for: IslandInputs(isDraggingOut: true, alert: .lowBattery(level: 5))), .expanded)
    }
}

final class BatteryAlertPolicyTests: XCTestCase {
    private func snapshot(_ level: Int, plugged: Bool = false, charging: Bool? = nil) -> PowerSnapshot {
        PowerSnapshot(level: level, isCharging: charging ?? plugged, isPluggedIn: plugged)
    }

    func testFirstReadingIsSilent() {
        var policy = BatteryAlertPolicy()
        XCTAssertNil(policy.evaluate(snapshot(50, plugged: true), chargingAlerts: true, lowBatteryAlerts: true))
    }

    func testPlugAndUnplug() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(50), chargingAlerts: true, lowBatteryAlerts: true)
        XCTAssertEqual(policy.evaluate(snapshot(50, plugged: true), chargingAlerts: true, lowBatteryAlerts: true), .charging(level: 50))
        XCTAssertNil(policy.evaluate(snapshot(51, plugged: true), chargingAlerts: true, lowBatteryAlerts: true))
        XCTAssertEqual(policy.evaluate(snapshot(51), chargingAlerts: true, lowBatteryAlerts: true), .unplugged(level: 51))
    }

    func testPluggedInButNotCharging() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(100), chargingAlerts: true, lowBatteryAlerts: true)
        XCTAssertEqual(
            policy.evaluate(snapshot(100, plugged: true, charging: false), chargingAlerts: true, lowBatteryAlerts: true),
            .pluggedIn(level: 100)
        )
    }

    func testChargingAlertsCanBeDisabled() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(50), chargingAlerts: false, lowBatteryAlerts: true)
        XCTAssertNil(policy.evaluate(snapshot(50, plugged: true), chargingAlerts: false, lowBatteryAlerts: true))
    }

    func testLowBatteryFiresOncePerThreshold() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(25), chargingAlerts: true, lowBatteryAlerts: true)
        XCTAssertNil(policy.evaluate(snapshot(21), chargingAlerts: true, lowBatteryAlerts: true))
        XCTAssertEqual(policy.evaluate(snapshot(20), chargingAlerts: true, lowBatteryAlerts: true), .lowBattery(level: 20))
        XCTAssertNil(policy.evaluate(snapshot(19), chargingAlerts: true, lowBatteryAlerts: true))
        XCTAssertNil(policy.evaluate(snapshot(11), chargingAlerts: true, lowBatteryAlerts: true))
        XCTAssertEqual(policy.evaluate(snapshot(10), chargingAlerts: true, lowBatteryAlerts: true), .lowBattery(level: 10))
        XCTAssertNil(policy.evaluate(snapshot(9), chargingAlerts: true, lowBatteryAlerts: true))
    }

    func testThresholdsResetAfterCharging() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(21), chargingAlerts: true, lowBatteryAlerts: true)
        XCTAssertEqual(policy.evaluate(snapshot(20), chargingAlerts: true, lowBatteryAlerts: true), .lowBattery(level: 20))
        _ = policy.evaluate(snapshot(20, plugged: true), chargingAlerts: true, lowBatteryAlerts: true)
        _ = policy.evaluate(snapshot(22), chargingAlerts: true, lowBatteryAlerts: true)
        XCTAssertEqual(policy.evaluate(snapshot(20), chargingAlerts: true, lowBatteryAlerts: true), .lowBattery(level: 20))
    }

    func testNoLowBatteryNagIfLaunchedBelowThreshold() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(15), chargingAlerts: true, lowBatteryAlerts: true)
        XCTAssertNil(policy.evaluate(snapshot(14), chargingAlerts: true, lowBatteryAlerts: true))
        XCTAssertEqual(policy.evaluate(snapshot(10), chargingAlerts: true, lowBatteryAlerts: true), .lowBattery(level: 10))
    }

    func testLowBatteryAlertsCanBeDisabled() {
        var policy = BatteryAlertPolicy()
        _ = policy.evaluate(snapshot(21), chargingAlerts: true, lowBatteryAlerts: false)
        XCTAssertNil(policy.evaluate(snapshot(20), chargingAlerts: true, lowBatteryAlerts: false))
    }
}
