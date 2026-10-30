import AppKit
import Combine
import NotchCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsModel!
    private var music: MusicController!
    private var weather: WeatherService!
    private var battery: BatteryMonitor!
    private var shelf: ShelfModel!
    private var favicons: FaviconCache!
    private var island: IslandViewModel!
    private var windowController: NotchWindowController!
    private var settingsWindow: SettingsWindowController!
    private var statusItem: StatusItemController!
    private var cancellables = Set<AnyCancellable>()

    private let arguments = ProcessInfo.processInfo.arguments

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        if handOffToRunningInstance() { return }

        if arguments.contains("--reset") {
            [StorageKeys.settings, StorageKeys.shelf, StorageKeys.weatherCache].forEach {
                UserDefaults.standard.removeObject(forKey: $0)
            }
        }

        NSApp.mainMenu = MainMenu.make(target: self)

        settings = SettingsModel()
        music = MusicController()
        weather = WeatherService(location: settings.settings.weatherLocation, unit: settings.settings.temperatureUnit)
        battery = BatteryMonitor()
        shelf = ShelfModel()
        favicons = FaviconCache()
        island = IslandViewModel(
            settings: settings, music: music, weather: weather,
            battery: battery, shelf: shelf, favicons: favicons
        )
        windowController = NotchWindowController(model: island)
        settingsWindow = SettingsWindowController(
            settings: settings, weather: weather, shelf: shelf, favicons: favicons, island: island
        )
        statusItem = StatusItemController(
            openIsland: { [weak self] in self?.island.previewExpanded(seconds: 6) },
            openSettings: { [weak self] in self?.showSettings(nil) }
        )
        island.openSettingsHandler = { [weak self] pane in self?.showSettings(pane) }

        settings.$settings
            .map(\.showMenuBarIcon)
            .removeDuplicates()
            .sink { [weak self] visible in self?.statusItem.setVisible(visible) }
            .store(in: &cancellables)

        if arguments.contains("--demo") {
            runDemo()
        } else if !settings.settings.hasCompletedOnboarding {
            settings.settings.hasCompletedOnboarding = true
            showSettings(.general)
            island.previewExpanded(seconds: 4)
        }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening MacNotch again from Finder or Launchpad shows Settings.
        showSettings(nil)
        return false
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc func showSettingsAction(_ sender: Any?) {
        showSettings(nil)
    }

    @objc func showAboutAction(_ sender: Any?) {
        showSettings(.about)
    }

    private func showSettings(_ pane: SettingsPane?) {
        settingsWindow.show(pane)
    }

    /// If MacNotch is already running (for example a second copy), let that one handle it.
    private func handOffToRunningInstance() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard let existing = others.first else { return false }
        existing.activate()
        NSApp.terminate(nil)
        return true
    }

    /// Scripted tour used by CI to screenshot every state of the real app.
    private func runDemo() {
        let artwork = DemoContent.artwork()
        music.preview(track: DemoContent.track, state: .playing, artwork: artwork, elapsed: 150)
        let steps: [(Double, () -> Void)] = [
            (1.0, { [weak self] in self?.island.forceInputs(IslandInputs(nowPlayingActive: true)) }),
            (4.0, { [weak self] in self?.island.forceInputs(IslandInputs(nowPlayingActive: true, alert: .charging(level: 82))) }),
            (7.0, { [weak self] in self?.island.forceInputs(IslandInputs(isPinnedOpen: true, nowPlayingActive: true)) }),
            (11.0, { [weak self] in self?.settings.settings.islandMaterial = .black }),
            (14.0, { [weak self] in
                self?.settings.settings.islandMaterial = .liquidGlass
                self?.island.forceInputs(IslandInputs())
                self?.showSettings(.general)
            }),
            (17.0, { [weak self] in self?.showSettings(.webPages) }),
            (20.0, { [weak self] in self?.showSettings(.appearance) })
        ]
        for (delay, action) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { action() }
            }
        }
    }
}

enum MainMenu {
    /// Accessory apps still need an Edit menu so copy and paste work in Settings text fields.
    @MainActor
    static func make(target: AppDelegate) -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "MacNotch")
        let about = appMenu.addItem(withTitle: "About MacNotch", action: #selector(AppDelegate.showAboutAction(_:)), keyEquivalent: "")
        about.target = target
        appMenu.addItem(.separator())
        let settings = appMenu.addItem(withTitle: "Settings…", action: #selector(AppDelegate.showSettingsAction(_:)), keyEquivalent: ",")
        settings.target = target
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MacNotch", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit MacNotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }
}
