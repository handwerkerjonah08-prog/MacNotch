import AppKit
import Combine
import NotchCore
import SwiftUI

/// Borderless, transparent panel that floats above the menu bar on every Space, including full screen.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Never let AppKit push the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

    static func make() -> NotchPanel {
        let panel = NotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.appearance = NSAppearance(named: .darkAqua)
        return panel
    }
}

/// Places the panel over the notch and turns raw mouse/drag events into island input.
///
/// The panel ignores the mouse except while the pointer is over the island, so the menu bar and
/// windows underneath keep working. Global mouse monitors don't need any permission.
@MainActor
final class NotchWindowController {
    let panel: NotchPanel
    private let model: IslandViewModel
    private let hostingView: NSHostingView<IslandRootView>
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var isPointerInside = false
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var trackingTimer: Timer?
    private var dragEndTask: Task<Void, Never>?

    init(model: IslandViewModel) {
        self.model = model
        panel = NotchPanel.make()
        hostingView = NSHostingView(rootView: IslandRootView(model: model))
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        layoutPanel()
        panel.orderFrontRegardless()
        installMonitors()
        observeSystem()

        model.presentationChanged = { [weak self] _ in
            self?.presentationDidChange()
        }
    }

    // MARK: Layout

    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    func layoutPanel() {
        guard let screen = Self.targetScreen() else { return }
        let geometry = NotchGeometry.compute(
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width
        )
        model.updateGeometry(geometry, maxWidth: screen.frame.width - 16)

        // Room for the largest island plus its shadow.
        let maximum = model.maximumSize
        let width = min(screen.frame.width, maximum.width + 80)
        let height = maximum.height + 60
        let frame = CGRect(
            x: (geometry.notchRect.midX - width / 2).rounded(),
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    /// The island's current frame in screen coordinates, padded to be forgiving.
    func hitZone() -> CGRect {
        let size = model.islandSize
        let frame = panel.frame
        var rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        if model.presentation.isExpanded {
            rect = rect.insetBy(dx: -4, dy: -4)
        } else {
            rect = rect.insetBy(dx: -8, dy: 0)
            rect.origin.y -= 6
            rect.size.height += 6
        }
        // Include the very top row of pixels.
        rect.size.height += 2
        return rect
    }

    private func dragZone() -> CGRect {
        let zone = hitZone()
        if model.presentation.isExpanded {
            return zone.insetBy(dx: -40, dy: -40)
        }
        var rect = zone.insetBy(dx: -110, dy: 0)
        rect.origin.y -= 70
        rect.size.height += 70
        return rect
    }

    // MARK: Events

    private func installMonitors() {
        let globalMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: globalMask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                self?.handle(type, isLocal: false)
            }
        }) {
            monitors.append(monitor)
        }

        let localMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: localMask, handler: { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated {
                self?.handle(type, isLocal: true)
            }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func handle(_ type: NSEvent.EventType, isLocal: Bool) {
        let location = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown, .rightMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            if !hitZone().contains(location) {
                model.clickedOutside()
            }
        case .leftMouseDragged where !isLocal:
            updateFileDrag(at: location)
        case .leftMouseUp where !isLocal:
            finishFileDrag()
        default:
            break
        }
        updatePointer(at: location)
    }

    private func updatePointer(at location: CGPoint) {
        let inside = hitZone().contains(location) || (model.presentation.isExpanded && model.isDropTargeted)
        if panel.ignoresMouseEvents == inside {
            panel.ignoresMouseEvents = !inside
        }
        if inside != isPointerInside {
            isPointerInside = inside
            model.mouseInsideChanged(inside)
            updateTrackingTimer()
        }
    }

    private func updateFileDrag(at location: CGPoint) {
        guard model.acceptsFileDrops else { return }
        let pasteboard = NSPasteboard(name: .drag)
        guard pasteboard.changeCount != dragChangeCount,
              pasteboard.types?.contains(.fileURL) == true
        else { return }

        dragEndTask?.cancel()
        let near = dragZone().contains(location)
        model.setFileDragNearby(near)
        if near {
            panel.ignoresMouseEvents = false
        }
    }

    private func finishFileDrag() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        dragEndTask?.cancel()
        // Give the drop a moment to land before collapsing.
        dragEndTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, let self else { return }
            self.model.setFileDragNearby(false)
            self.updatePointer(at: NSEvent.mouseLocation)
        }
    }

    /// Backstop that catches fast exits the event stream can miss. Only runs while it matters.
    private func updateTrackingTimer() {
        let needed = isPointerInside || model.presentation.isExpanded
        if needed, trackingTimer == nil {
            trackingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updatePointer(at: NSEvent.mouseLocation)
                }
            }
        } else if !needed {
            trackingTimer?.invalidate()
            trackingTimer = nil
        }
    }

    private func presentationDidChange() {
        updatePointer(at: NSEvent.mouseLocation)
        updateTrackingTimer()
    }

    // MARK: System changes

    private func observeSystem() {
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { controller in
            controller.layoutPanel()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { controller in
            controller.panel.orderFrontRegardless()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { controller in
            controller.layoutPanel()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { controller in
            controller.layoutPanel()
        }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        perform action: @escaping @MainActor (NotchWindowController) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                action(self)
            }
        }
        observers.append((center, token))
    }
}
