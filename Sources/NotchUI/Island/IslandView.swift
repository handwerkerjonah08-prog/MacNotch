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
    }
}

struct IslandView: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var settings: SettingsModel

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
        .contentShape(shape)
        .shadow(
            color: Color.black.opacity(presentation.isExpanded ? 0.45 : 0),
            radius: presentation.isExpanded ? 22 : 0,
            x: 0,
            y: presentation.isExpanded ? 10 : 0
        )
        .scaleEffect(peek ? 1.035 : 1, anchor: .top)
        .onTapGesture { model.islandTapped() }
        .onDrop(of: [.fileURL], isTargeted: $model.isDropTargeted) { providers in
            model.handleDrop(providers)
        }
        .contextMenu {
            Button("Settings…") { model.openSettings() }
            Divider()
            Button("Quit MacNotch") { NSApp.terminate(nil) }
        }
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
        case .shelfAdded:
            return nil
        }
    }

    private var leadingSymbol: String {
        switch alert {
        case .charging, .pluggedIn: return "bolt.fill"
        case .unplugged: return "powerplug.fill"
        case .lowBattery: return "exclamationmark.triangle.fill"
        case .shelfAdded: return "tray.and.arrow.down.fill"
        }
    }

    private var leadingText: String {
        switch alert {
        case .charging: return "Charging"
        case .pluggedIn: return "Plugged In"
        case .unplugged: return "On Battery"
        case .lowBattery: return "Low Battery"
        case .shelfAdded: return "Added to Shelf"
        }
    }

    private var trailingText: String {
        switch alert {
        case .charging(let level), .pluggedIn(let level), .unplugged(let level), .lowBattery(let level):
            return "\(level)%"
        case .shelfAdded(let count):
            return count == 1 ? "1 file" : "\(count) files"
        }
    }

    private var tint: Color {
        switch alert {
        case .charging: return Color(red: 0.2, green: 0.84, blue: 0.29)
        case .pluggedIn, .unplugged: return Color.white.opacity(0.9)
        case .lowBattery(let level): return level <= 10 ? Color(red: 1, green: 0.27, blue: 0.23) : Color(red: 1, green: 0.62, blue: 0.04)
        case .shelfAdded: return Color(red: 0.25, green: 0.6, blue: 1)
        }
    }

    private var alertTextColor: Color {
        if case .lowBattery = alert { return tint }
        return .white
    }
}
