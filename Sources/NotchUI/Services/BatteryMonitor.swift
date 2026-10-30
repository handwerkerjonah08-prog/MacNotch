import Foundation
import IOKit.ps
import NotchCore

/// Watches the internal battery through IOKit power source notifications.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var snapshot: PowerSnapshot?

    /// Called on every change, after `snapshot` updates.
    var onChange: ((PowerSnapshot) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    init(live: Bool = true) {
        guard live else { return }
        snapshot = Self.read()
        install()
    }

    func preview(_ snapshot: PowerSnapshot?) {
        self.snapshot = snapshot
    }

    private func install() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                monitor.update()
            }
        }
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else {
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
    }

    private func update() {
        guard let reading = Self.read(), reading != snapshot else { return }
        snapshot = reading
        onChange?(reading)
    }

    /// Nil on Macs without a battery.
    nonisolated static func read() -> PowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "InternalBattery"
            else { continue }

            let current = (description["Current Capacity"] as? NSNumber)?.doubleValue ?? 0
            let maximum = (description["Max Capacity"] as? NSNumber)?.doubleValue ?? 100
            let level = maximum > 0 ? Int((current / maximum * 100).rounded()) : Int(current)
            let charging = (description["Is Charging"] as? NSNumber)?.boolValue ?? false
            let pluggedIn = description["Power Source State"] as? String == "AC Power"
            return PowerSnapshot(level: min(max(level, 0), 100), isCharging: charging, isPluggedIn: pluggedIn)
        }
        return nil
    }
}
