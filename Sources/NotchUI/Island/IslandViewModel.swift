import AppKit
import Combine
import NotchCore
import SwiftUI

/// What is being dragged toward the notch.
enum DragKind: Equatable {
    case none
    /// Files from Finder, headed for the shelf.
    case file
    /// A web link (for example from Safari's address bar), saved as a web page.
    case link
}

/// Owns the island's state. Inputs (hover, music, power, drags) go in; a presentation comes out.
@MainActor
final class IslandViewModel: ObservableObject {
    @Published private(set) var presentation: IslandPresentation = .idle
    @Published private(set) var notch: NotchGeometry
    @Published private(set) var maxWidth: CGFloat
    @Published private(set) var isMouseInside = false
    @Published private(set) var isEditing = false
    @Published private(set) var dragKind: DragKind = .none
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
        let current = settings.settings
        return IslandMetrics.size(
            for: presentation,
            notch: notch.size,
            widgets: current.enabledWidgetKinds,
            shortcutCount: current.shortcuts.count,
            maxWidth: maxWidth,
            leading: current.notchLeading,
            trailing: current.notchTrailing
        )
    }

    var maximumSize: CGSize {
        IslandMetrics.maximumSize(notch: notch.size, maxWidth: maxWidth)
    }

    var acceptsFileDrops: Bool { settings.settings.isEnabled(.fileShelf) }
    var acceptsLinkDrops: Bool { settings.settings.isEnabled(.webPages) }

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
        endEditing()
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

    // MARK: Drags onto the notch

    /// Called while something is dragged near the notch, or with `.none` when the drag ends or moves away.
    func setDragNearby(_ kind: DragKind) {
        let accepted: DragKind
        switch kind {
        case .file: accepted = acceptsFileDrops ? .file : .none
        case .link: accepted = acceptsLinkDrops ? .link : .none
        case .none: accepted = .none
        }
        if dragKind != accepted {
            dragKind = accepted
        }
        inputs.isFileDragNearby = accepted != .none
        if accepted == .none {
            isDropTargeted = false
        }
    }

    /// Files go on the shelf; web links become saved web pages.
    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard acceptsFileDrops || acceptsLinkDrops else { return false }
        Task { [weak self] in
            let dropped = await ShelfModel.droppedURLs(from: providers)
            guard let self else { return }
            var alert: AlertKind?
            if self.acceptsFileDrops, !dropped.files.isEmpty {
                let added = self.shelf.add(dropped.files)
                if added > 0 { alert = .shelfAdded(count: added) }
            }
            if self.acceptsLinkDrops {
                for link in dropped.links {
                    if let saved = self.settings.settings.addShortcut(for: link) {
                        self.favicons.load(saved)
                        alert = .shortcutAdded(name: saved.name)
                    }
                }
            }
            self.isDropTargeted = false
            self.setDragNearby(.none)
            if let alert {
                self.showAlert(alert)
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
        endEditing()
        collapse()
        openSettingsHandler?(pane)
    }

    /// Opens Settings straight to the Add Web Page sheet.
    var addWebPageHandler: (() -> Void)?

    func addWebPage() {
        endEditing()
        collapse()
        addWebPageHandler?()
    }

    // MARK: Edit mode (iPhone-style wiggle)

    func beginEditing() {
        guard !isEditing else { return }
        withAnimation(Theme.openSpring) { isEditing = true }
        inputs.isEditing = true
        if settings.settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }

    func endEditing() {
        guard isEditing else { return }
        withAnimation(Theme.openSpring) { isEditing = false }
        inputs.isEditing = false
    }

    func removeWidget(_ kind: WidgetKind) {
        withAnimation(Theme.openSpring) { settings.settings.setWidget(kind, enabled: false) }
    }

    func addWidget(_ kind: WidgetKind) {
        withAnimation(Theme.openSpring) { settings.settings.setWidget(kind, enabled: true) }
    }

    func moveWidget(_ kind: WidgetKind, toVisibleIndex index: Int) {
        guard settings.settings.enabledWidgetKinds.firstIndex(of: kind) != index else { return }
        withAnimation(Theme.openSpring) { settings.settings.moveEnabledWidget(kind, toEnabledIndex: index) }
    }

    func removeShortcut(_ id: UUID) {
        withAnimation(Theme.openSpring) { settings.settings.removeShortcut(id: id) }
    }

    func moveShortcut(_ id: UUID, to index: Int) {
        guard settings.settings.shortcuts.firstIndex(where: { $0.id == id }) != index else { return }
        withAnimation(Theme.openSpring) { settings.settings.moveShortcut(id: id, to: index) }
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
        copy.showsInfo = copy.showsInfo || settings.settings.showsNotchInfo
        if copy.isEditing != isEditing {
            withAnimation(Theme.openSpring) { isEditing = copy.isEditing }
        }
        self.inputs = copy
    }

    /// Sets what a drag is carrying without the window controller. Snapshots and tests only.
    func forceDragKind(_ kind: DragKind) {
        dragKind = kind
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
        inputs.showsInfo = newSettings.showsNotchInfo
        if !newSettings.showNowPlayingActivity {
            inputs.nowPlayingActive = false
        } else if music.state == .playing {
            inputs.nowPlayingActive = true
        }
        if (dragKind == .file && !newSettings.isEnabled(.fileShelf))
            || (dragKind == .link && !newSettings.isEnabled(.webPages)) {
            dragKind = .none
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
