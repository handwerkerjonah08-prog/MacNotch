import Foundation
import NotchCore
import ServiceManagement
import SwiftUI

/// Observable wrapper around `AppSettings` that saves every change.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: AppSettings {
        didSet {
            if settings != oldValue {
                store?.save(settings)
            }
        }
    }

    private let store: CodableDefaults<AppSettings>?

    init(live: Bool = true) {
        store = live ? CodableDefaults(key: StorageKeys.settings) : nil
        settings = store?.load() ?? .default
    }

    init(preview: AppSettings) {
        store = nil
        settings = preview
    }

    func resetToDefaults() {
        settings = .default
    }

    // MARK: Widgets

    func moveWidgets(from source: IndexSet, to destination: Int) {
        settings.widgets.move(fromOffsets: source, toOffset: destination)
    }

    func moveWidget(_ kind: WidgetKind, by offset: Int) {
        guard let index = settings.widgets.firstIndex(where: { $0.kind == kind }) else { return }
        let target = index + offset
        guard settings.widgets.indices.contains(target) else { return }
        settings.widgets.swapAt(index, target)
    }

    // MARK: Shortcuts

    func addShortcut(_ shortcut: WebShortcut) {
        settings.shortcuts.append(shortcut)
    }

    func updateShortcut(_ shortcut: WebShortcut) {
        guard let index = settings.shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        settings.shortcuts[index] = shortcut
    }

    func removeShortcut(id: UUID) {
        settings.shortcuts.removeAll { $0.id == id }
    }

    func moveShortcuts(from source: IndexSet, to destination: Int) {
        settings.shortcuts.move(fromOffsets: source, toOffset: destination)
    }

    func hasShortcut(for url: URL) -> Bool {
        let host = WebShortcut(name: "", url: url).host
        return settings.shortcuts.contains { $0.host == host && $0.url.path == url.path }
    }
}

enum LaunchAtLogin {
    enum Status {
        case enabled, disabled, requiresApproval, unavailable
    }

    static var status: Status {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .disabled
        case .notFound: return .unavailable
        @unknown default: return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
