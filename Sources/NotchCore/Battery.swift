import Foundation

public struct PowerSnapshot: Equatable, Sendable {
    public var level: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool

    public init(level: Int, isCharging: Bool, isPluggedIn: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }
}

/// Decides when a power change deserves an island alert. Pure value type so it is easy to test.
public struct BatteryAlertPolicy: Sendable {
    public let lowThresholds: [Int]
    private var last: PowerSnapshot?
    private var firedThresholds: Set<Int> = []

    public init(lowThresholds: [Int] = [20, 10]) {
        self.lowThresholds = lowThresholds.sorted()
    }

    public mutating func evaluate(
        _ snapshot: PowerSnapshot,
        chargingAlerts: Bool,
        lowBatteryAlerts: Bool
    ) -> AlertKind? {
        defer { last = snapshot }

        if snapshot.isPluggedIn {
            firedThresholds.removeAll()
        }

        // The first reading only establishes a baseline.
        guard let previous = last else {
            if !snapshot.isPluggedIn {
                // Don't nag about thresholds we were already below at launch.
                firedThresholds = Set(lowThresholds.filter { snapshot.level <= $0 })
            }
            return nil
        }

        if snapshot.isPluggedIn != previous.isPluggedIn {
            guard chargingAlerts else { return nil }
            if snapshot.isPluggedIn {
                return snapshot.isCharging ? .charging(level: snapshot.level) : .pluggedIn(level: snapshot.level)
            }
            return .unplugged(level: snapshot.level)
        }

        guard !snapshot.isPluggedIn, lowBatteryAlerts, snapshot.level < previous.level else { return nil }

        let crossed = lowThresholds.filter { snapshot.level <= $0 && !firedThresholds.contains($0) }
        guard !crossed.isEmpty else { return nil }
        crossed.forEach { firedThresholds.insert($0) }
        return .lowBattery(level: snapshot.level)
    }
}
