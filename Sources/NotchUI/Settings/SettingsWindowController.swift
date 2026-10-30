import AppKit
import NotchCore
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general, appearance, widgets, webPages, weather, shelf, about

    var id: SettingsPane { self }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .widgets: return "Widgets"
        case .webPages: return "Web Pages"
        case .weather: return "Weather"
        case .shelf: return "File Shelf"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .widgets: return "square.grid.2x2.fill"
        case .webPages: return "globe"
        case .weather: return "cloud.sun.fill"
        case .shelf: return "tray.full.fill"
        case .about: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: return Color(white: 0.55)
        case .appearance: return Color(red: 0.36, green: 0.42, blue: 0.95)
        case .widgets: return Color(red: 0.2, green: 0.55, blue: 1)
        case .webPages: return Color(red: 0.35, green: 0.35, blue: 0.85)
        case .weather: return Color(red: 0.2, green: 0.7, blue: 0.95)
        case .shelf: return Color(red: 1, green: 0.6, blue: 0.1)
        case .about: return Color(white: 0.5)
        }
    }
}

/// Holds the selected pane so the window can be opened to a specific page.
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var selection: SettingsPane? = .general
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let router = SettingsRouter()
    private let settings: SettingsModel
    private let weather: WeatherService
    private let shelf: ShelfModel
    private let favicons: FaviconCache
    private let island: IslandViewModel

    init(settings: SettingsModel, weather: WeatherService, shelf: ShelfModel, favicons: FaviconCache, island: IslandViewModel) {
        self.settings = settings
        self.weather = weather
        self.shelf = shelf
        self.favicons = favicons
        self.island = island
        super.init()
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func show(_ pane: SettingsPane? = nil) {
        if let pane {
            router.selection = pane
        }
        let window = self.window ?? makeWindow()
        self.window = window
        // Behave like a regular app while Settings is open so it comes to the front, gets a Dock
        // icon and works with Command-Tab. Back to menu-bar-only when it closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func makeWindow() -> NSWindow {
        let root = SettingsRootView(router: router, island: island)
            .environmentObject(settings)
            .environmentObject(weather)
            .environmentObject(shelf)
            .environmentObject(favicons)

        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = controller
        window.title = "MacNotch Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 700, height: 480)
        window.setContentSize(NSSize(width: 760, height: 560))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("MacNotchSettings")
        return window
    }
}
