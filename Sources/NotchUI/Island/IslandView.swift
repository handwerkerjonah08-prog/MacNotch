import AppKit
import NotchCore
import SwiftUI
import UniformTypeIdentifiers

/// Fills the transparent panel and pins the island to the top center.
struct IslandRootView: View {
    let model: IslandViewModel

    var body: some View {
        VStack(spacing: 0) {
            IslandView(model: model)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environmentObject(model.settings)
        .environmentObject(model.music)
        .environmentObject(model.weather)
        .environmentObject(model.battery)
        .environmentObject(model.shelf)
        .environmentObject(model.favicons)
        .environment(\.colorScheme, .dark)
        // The panel is never the key window; keep glass and controls in their active look anyway.
        .environment(\.controlActiveState, .key)
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var settings: SettingsModel
    @Environment(\.isSnapshotRendering) private var isSnapshot

    var body: some View {
        let presentation = model.presentation
        let size = model.size(for: presentation)
        let radii = IslandMetrics.radii(for: presentation)
        let shape = NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
        let useGlass = presentation.isExpanded && settings.settings.islandMaterial == .liquidGlass
        let peek = model.isMouseInside && !presentation.isExpanded

        ZStack(alignment: .top) {
            IslandShell(
                shape: shape,
                height: size.height,
                notchHeight: model.notch.size.height,
                useGlass: useGlass,
                tint: settings.settings.glassTint
            )

            content(for: presentation)
                .padding(.horizontal, radii.top)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .overlay {
            if useGlass {
                DarkenedEdge(shape: shape)
                    .transition(.opacity)
            }
        }
        .contentShape(shape)
        .shadow(
            color: Color.black.opacity(presentation.isExpanded ? 0.45 : 0),
            radius: presentation.isExpanded ? 22 : 0,
            x: 0,
            y: presentation.isExpanded ? 10 : 0
        )
        .scaleEffect(peek ? 1.035 : 1, anchor: .top)
        .onTapGesture { model.islandTapped() }
        .modifier(IslandInteractions(model: model, enabled: !isSnapshot))
        .animation(Theme.microSpring, value: peek)
        .animation(Theme.openSpring, value: settings.settings.enabledWidgetKinds)
        .animation(Theme.openSpring, value: settings.settings.shortcuts.count)
    }

    @ViewBuilder
    private func content(for presentation: IslandPresentation) -> some View {
        let notch = model.notch.size
        switch presentation {
        case .idle:
            Color.clear
        case .compactInfo:
            CompactInfoView(notch: notch)
                .transition(.islandContent)
        case .compactNowPlaying:
            CompactNowPlayingView(notch: notch)
                .transition(.islandContent)
        case .alert(let alert):
            AlertActivityView(alert: alert, notch: notch)
                .transition(.islandContent)
        case .expanded:
            ExpandedIslandView(model: model)
                .transition(.islandContent)
        }
    }
}

/// File drops and the right-click menu. Skipped in snapshots because ImageRenderer can't draw
/// the AppKit views behind them.
private struct IslandInteractions: ViewModifier {
    @ObservedObject var model: IslandViewModel
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrop(of: [.fileURL, .url], isTargeted: $model.isDropTargeted) { providers in
                    model.handleDrop(providers)
                }
                .contextMenu {
                    Button("Edit Widgets") { model.beginEditing() }
                    Button("Settings…") { model.openSettings() }
                    Divider()
                    Button("Quit MacNotch") { NSApp.terminate(nil) }
                }
        } else {
            content
        }
    }
}

/// The island's body: solid black where it meets the notch, Liquid Glass when expanded.
struct IslandShell: View {
    let shape: NotchShape
    let height: CGFloat
    let notchHeight: CGFloat
    let useGlass: Bool
    let tint: Double

    var body: some View {
        let notchFraction = height > 0 ? min(1, notchHeight / height) : 1
        ZStack {
            if useGlass {
                GlassFill(shape: shape, tint: tint)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
                // A black band keeps the hardware notch invisible, then melts into the glass.
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: notchFraction * 0.85),
                            .init(color: .black.opacity(0), location: min(1, notchFraction + 0.3))
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                SpecularRim(shape: shape, clearFraction: notchFraction)
            } else {
                shape.fill(Color.black)
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            }
        }
    }
}

// MARK: - Compact presentations

/// Leading and trailing regions either side of the notch (ActivityKit's compact layout).
struct CompactLayout<Leading: View, Trailing: View>: View {
    let notch: CGSize
    let wing: CGFloat
    let leading: Leading
    let trailing: Trailing

    init(notch: CGSize, wing: CGFloat, @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.notch = notch
        self.wing = wing
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: wing, height: notch.height, alignment: .leading)
            Color.clear
                .frame(width: notch.width, height: notch.height)
            trailing
                .frame(width: wing, height: notch.height, alignment: .trailing)
        }
    }
}

struct CompactNowPlayingView: View {
    let notch: CGSize
    @EnvironmentObject private var music: MusicController

    var body: some View {
        let wing = IslandMetrics.compactWingWidth(notch: notch)
        let art = min(22, notch.height - 10)
        CompactLayout(notch: notch, wing: wing) {
            ArtworkView(image: music.artwork, size: art, radius: art * 0.28)
                .id(music.track?.key ?? "none")
                .transition(.wingContent)
                .padding(.leading, 7)
        } trailing: {
            WaveformView(isPlaying: music.isPlaying, color: music.accent, barCount: 4, barWidth: 2.6, maxHeight: art * 0.72)
                .padding(.trailing, 9)
        }
        .animation(Theme.openSpring, value: music.track?.key)
    }
}

/// Whatever the user picked to sit either side of the notch.
struct CompactInfoView: View {
    let notch: CGSize
    @EnvironmentObject private var settings: SettingsModel

    var body: some View {
        let current = settings.settings
        CompactLayout(notch: notch, wing: IslandMetrics.infoWingWidth(leading: current.notchLeading, trailing: current.notchTrailing)) {
            NotchSlotView(slot: current.notchLeading)
                .padding(.leading, 10)
        } trailing: {
            NotchSlotView(slot: current.notchTrailing)
                .padding(.trailing, 10)
        }
    }
}

struct NotchSlotView: View {
    let slot: NotchSlot
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var shelf: ShelfModel

    var body: some View {
        HStack(spacing: 5) {
            switch slot {
            case .none:
                EmptyView()
            case .weather:
                if let snapshot = weather.snapshot {
                    Image(systemName: snapshot.condition.symbolName)
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 12))
                    Text(snapshot.temperatureText)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "cloud.fill").font(.system(size: 12))
                }
            case .battery:
                if let power = battery.snapshot {
                    Text("\(power.level)%")
                    BatteryGlyph(level: power.level, color: Theme.batteryColor(level: power.level, charging: power.isCharging), width: 22, height: 11)
                } else {
                    Image(systemName: "powerplug.fill").font(.system(size: 11))
                }
            case .time:
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.hour().minute())
                }
            case .date:
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.abbreviated).day())
                }
            case .shelf:
                Image(systemName: shelf.items.isEmpty ? "tray" : "tray.full.fill")
                    .font(.system(size: 12))
                if !shelf.items.isEmpty {
                    Text("\(shelf.items.count)")
                }
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(.white)
        .lineLimit(1)
        .fixedSize()
    }
}

struct AlertActivityView: View {
    let alert: AlertKind
    let notch: CGSize

    var body: some View {
        CompactLayout(notch: notch, wing: IslandMetrics.alertWingWidth(for: alert)) {
            HStack(spacing: 5) {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: alert)
                Text(leadingText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(alertTextColor)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.leading, 10)
        } trailing: {
            HStack(spacing: 5) {
                Text(trailingText)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(alertTextColor)
                    .lineLimit(1)
                    .fixedSize()
                if let level = batteryLevel {
                    BatteryGlyph(level: level, color: tint)
                }
            }
            .padding(.trailing, 10)
        }
    }

    private var batteryLevel: Int? {
        switch alert {
        case .charging(let level), .pluggedIn(let level), .unplugged(let level), .lowBattery(let level):
            return level
        case .shelfAdded, .shortcutAdded:
            return nil
        }
    }

    private var leadingSymbol: String {
        switch alert {
        case .charging, .pluggedIn: return "bolt.fill"
        case .unplugged: return "powerplug.fill"
        case .lowBattery: return "exclamationmark.triangle.fill"
        case .shelfAdded: return "tray.and.arrow.down.fill"
        case .shortcutAdded: return "globe"
        }
    }

    private var leadingText: String {
        switch alert {
        case .charging: return "Charging"
        case .pluggedIn: return "Plugged In"
        case .unplugged: return "On Battery"
        case .lowBattery: return "Low Battery"
        case .shelfAdded: return "Added to Shelf"
        case .shortcutAdded: return "Saved"
        }
    }

    private var trailingText: String {
        switch alert {
        case .charging(let level), .pluggedIn(let level), .unplugged(let level), .lowBattery(let level):
            return "\(level)%"
        case .shelfAdded(let count):
            return count == 1 ? "1 file" : "\(count) files"
        case .shortcutAdded(let name):
            return name.count > 14 ? String(name.prefix(13)) + "…" : name
        }
    }

    private var tint: Color {
        switch alert {
        case .charging: return Theme.green
        case .pluggedIn, .unplugged: return Color.white.opacity(0.9)
        case .lowBattery(let level): return level <= 10 ? Theme.red : Theme.orange
        case .shelfAdded, .shortcutAdded: return Theme.blue
        }
    }

    private var alertTextColor: Color {
        if case .lowBattery = alert { return tint }
        return .white
    }
}
