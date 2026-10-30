import AppKit
import Combine
import NotchCore
import SwiftUI

/// Owns the island's state. Inputs (hover, music, power, drags) go in; a presentation comes out.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .idle
    @Published private(set) var notch: NotchGeometry
    @Published private(set) var maxWidth: CGFloat
    @Published private(set) var isMouseInside = false
    @Published var isDropTargeted = false

    let settings: SettingsModel
    let music: MusicController
    let weather: WeatherService
    let battery: BatteryMonitor
    let shelf: ShelfModel
    let favicons: FaviconCache

    var openSettingsHandler: ((SettingsPane?) -> Void)?
    var presentationChanged: ((IslandPresentation) -> Void)?

    private var inputs = IslandInputs() {
        didSet {
            if inputs != oldValue { recompute() }
        }
    }
    private var policy = BatteryAlertPolicy()
    private var hoverTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var lingerTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var dragOutTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(
        settings: SettingsModel,
        music: MusicController,
        weather: WeatherService,
        battery: BatteryMonitor,
        shelf: ShelfModel,
        favicons: FaviconCache,
        notch: NotchGeometry = NotchGeometry(
            notchRect: CGRect(x: 0, y: 0, width: NotchGeometry.fallbackNotchWidth, height: 32),
            hasHardwareNotch: false
        ),
        maxWidth: CGFloat = 1400
    ) {
        self.settings = settings
        self.music = music
        self.weather = weather
        self.battery = battery
        self.shelf = shelf
        self.favicons = favicons
        self.notch = notch
        self.maxWidth = maxWidth
        inputs.trigger = settings.settings.expandTrigger
        bind()
    }

    // MARK: Sizes

    var islandSize: CGSize { size(for: presentation) }

    func size(for presentation: IslandPresentation) -> CGSize {
        IslandMetrics.size(
            for: presentation,
            notch: notch.size,
            widgets: settings.settings.enabledWidgetKinds,
            shortcutCount: settings.settings.shortcuts.count,
            maxWidth: maxWidth
        )
    }

    var maximumSize: CGSize {
        IslandMetrics.maximumSize(notch: notch.size, maxWidth: maxWidth)
    }

    var acceptsFileDrops: Bool { settings.settings.isEnabled(.fileShelf) }

    func updateGeometry(_ geometry: NotchGeometry, maxWidth: CGFloat) {
        notch = geometry
        self.maxWidth = maxWidth
    }

    // MARK: Pointer input (from the window controller)

    func mouseInsideChanged(_ inside: Bool) {
        guard inside != isMouseInside else { return }
        withAnimation(Theme.microSpring) { isMouseInside = inside }
        hoverTask?.cancel()

        if inside {
            guard inputs.trigger == .hover else { return }
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000)
                guard !Task.isCancelled else { return }
                self?.inputs.isHovering = true
            }
        } else {
            let delay: UInt64 = inputs.trigger == .hover ? 220_000_000 : 450_000_000
            hoverTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: delay)
                guard !Task.isCancelled, let self else { return }
                self.inputs.isHovering = false
                self.inputs.isPinnedOpen = false
            }
        }
    }

    func islandTapped() {
        guard !presentation.isExpanded else { return }
        hoverTask?.cancel()
        inputs.isPinnedOpen = true
    }

    func clickedOutside() {
        inputs.isPinnedOpen = false
        if !isMouseInside {
            inputs.isHovering = false
        }
    }

    /// Closes the island after an action, the way iPhone collapses after you tap a control.
    func collapse() {
        hoverTask?.cancel()
        inputs.isPinnedOpen = false
        inputs.isHovering = false
    }

    // MARK: File drags

    func setFileDragNearby(_ nearby: Bool) {
        guard acceptsFileDrops || !nearby else { return }
        inputs.isFileDragNearby = nearby
        if !nearby {
            isDropTargeted = false
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard acceptsFileDrops else { return false }
        Task { [weak self] in
            let urls = await ShelfModel.fileURLs(from: providers)
            guard let self else { return }
            let added = self.shelf.add(urls)
            self.isDropTargeted = false
            self.inputs.isFileDragNearby = false
            if added > 0 {
                self.showAlert(.shelfAdded(count: added))
            }
        }
        return true
    }

    /// Keeps the island open while a shelf item is dragged out, until the mouse button is released.
    func beginDragOut() {
        inputs.isDraggingOut = true
        dragOutTimer?.invalidate()
        dragOutTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                timer.invalidate()
                self?.endDragOut()
            }
        }
    }

    private func endDragOut() {
        dragOutTimer = nil
        inputs.isDraggingOut = false
        shelf.pruneMissing()
    }

    // MARK: Actions

    func openSettings(_ pane: SettingsPane? = nil) {
        collapse()
        openSettingsHandler?(pane)
    }

    func open(_ shortcut: WebShortcut) {
        NSWorkspace.shared.open(shortcut.url)
        collapse()
    }

    func showAlert(_ alert: AlertKind) {
        alertTask?.cancel()
        inputs.alert = alert
        alertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(alert.duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.inputs.alert = nil
        }
    }

    /// Opens the island briefly, used on first launch and from Settings.
    func previewExpanded(seconds: Double = 3.5) {
        previewTask?.cancel()
        inputs.isPinnedOpen = true
        previewTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, !self.isMouseInside else { return }
            self.inputs.isPinnedOpen = false
        }
    }

    /// Sets presentation inputs directly. Used by snapshot rendering and the CI demo.
    func forceInputs(_ inputs: IslandInputs) {
        var copy = inputs
        copy.trigger = settings.settings.expandTrigger
        self.inputs = copy
    }

    // MARK: Bindings

    private func bind() {
        settings.$settings
            .sink { [weak self] newSettings in self?.settingsChanged(newSettings) }
            .store(in: &cancellables)

        music.$state
            .removeDuplicates()
            .sink { [weak self] state in self?.musicStateChanged(state) }
            .store(in: &cancellables)

        if let snapshot = battery.snapshot {
            _ = policy.evaluate(snapshot, chargingAlerts: false, lowBatteryAlerts: false)
        }
        battery.onChange = { [weak self] snapshot in
            self?.powerChanged(snapshot)
        }
    }

    private func settingsChanged(_ newSettings: AppSettings) {
        inputs.trigger = newSettings.expandTrigger
        if !newSettings.showNowPlayingActivity {
            inputs.nowPlayingActive = false
        } else if music.state == .playing {
            inputs.nowPlayingActive = true
        }
        if !newSettings.isEnabled(.fileShelf) {
            inputs.isFileDragNearby = false
        }
        weather.configure(location: newSettings.weatherLocation, unit: newSettings.temperatureUnit)
        favicons.load(newSettings.shortcuts)
    }

    private func musicStateChanged(_ state: PlaybackState) {
        lingerTask?.cancel()
        switch state {
        case .playing:
            inputs.nowPlayingActive = settings.settings.showNowPlayingActivity
        case .paused:
            // Keep the compact activity around briefly after pausing, like iOS.
            lingerTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                self?.inputs.nowPlayingActive = false
            }
        case .stopped:
            inputs.nowPlayingActive = false
        }
    }

    private func powerChanged(_ snapshot: PowerSnapshot) {
        let current = settings.settings
        if let alert = policy.evaluate(
            snapshot,
            chargingAlerts: current.chargingAlerts,
            lowBatteryAlerts: current.lowBatteryAlerts
        ) {
            showAlert(alert)
        }
    }

    private func recompute() {
        let next = IslandStateMachine.presentation(for: inputs)
        guard next != presentation else { return }
        let wasExpanded = presentation.isExpanded
        withAnimation(next.isExpanded ? Theme.openSpring : Theme.closeSpring) {
            presentation = next
        }
        if next.isExpanded && !wasExpanded {
            didExpand()
        }
        presentationChanged?(next)
    }

    private func didExpand() {
        if settings.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        music.refreshState()
        weather.refreshIfStale()
        shelf.pruneMissing()
        favicons.load(settings.settings.shortcuts)
    }
}
