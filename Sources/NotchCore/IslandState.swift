import Foundation

/// Transient live activities that briefly take over the compact island, like iPhone's charging indicator.
public enum AlertKind: Equatable, Sendable {
    case charging(level: Int)
    case pluggedIn(level: Int)
    case unplugged(level: Int)
    case lowBattery(level: Int)
    case shelfAdded(count: Int)

    public var duration: TimeInterval {
        switch self {
        case .lowBattery: return 4.0
        case .shelfAdded: return 1.8
        default: return 2.8
        }
    }
}

/// What the island is currently showing. Mirrors ActivityKit's minimal/compact/expanded presentations.
public enum IslandPresentation: Equatable, Sendable {
    case idle
    case compactNowPlaying
    case alert(AlertKind)
    case expanded

    public var isExpanded: Bool { self == .expanded }
}

public struct IslandInputs: Equatable, Sendable {
    public var isHovering = false
    public var isPinnedOpen = false
    public var isFileDragNearby = false
    public var isDraggingOut = false
    public var nowPlayingActive = false
    public var alert: AlertKind?
    public var trigger: ExpandTrigger = .hover

    public init(
        isHovering: Bool = false, isPinnedOpen: Bool = false, isFileDragNearby: Bool = false,
        isDraggingOut: Bool = false, nowPlayingActive: Bool = false, alert: AlertKind? = nil,
        trigger: ExpandTrigger = .hover
    ) {
        self.isHovering = isHovering
        self.isPinnedOpen = isPinnedOpen
        self.isFileDragNearby = isFileDragNearby
        self.isDraggingOut = isDraggingOut
        self.nowPlayingActive = nowPlayingActive
        self.alert = alert
        self.trigger = trigger
    }
}

public enum IslandStateMachine {
    public static func presentation(for inputs: IslandInputs) -> IslandPresentation {
        if inputs.isFileDragNearby || inputs.isDraggingOut || inputs.isPinnedOpen {
            return .expanded
        }
        if inputs.trigger == .hover && inputs.isHovering {
            return .expanded
        }
        if let alert = inputs.alert {
            return .alert(alert)
        }
        if inputs.nowPlayingActive {
            return .compactNowPlaying
        }
        return .idle
    }
}
