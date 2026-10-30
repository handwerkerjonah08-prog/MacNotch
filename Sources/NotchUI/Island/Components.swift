import AppKit
import NotchCore
import SwiftUI

// MARK: - Waveform

/// Animated level bars tinted with the artwork color, like the iPhone island's audio indicator.
struct WaveformView: View {
    var isPlaying: Bool
    var color: Color
    var barCount = 4
    var barWidth: CGFloat = 3
    var maxHeight: CGFloat = 16

    private static let speeds: [Double] = [5.3, 7.1, 6.2, 8.4, 5.9]
    private static let phases: [Double] = [0, 1.7, 3.1, 0.9, 2.4]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: barWidth * 0.75) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color)
                        .frame(width: barWidth, height: height(for: index, time: time))
                }
            }
            .frame(height: maxHeight)
        }
        .animation(.easeInOut(duration: 0.3), value: isPlaying)
        .accessibilityHidden(true)
    }

    private func height(for index: Int, time: Double) -> CGFloat {
        guard isPlaying else { return barWidth }
        let speeds = Self.speeds, phases = Self.phases
        let a = sin(time * speeds[index % speeds.count] + phases[index % phases.count])
        let b = sin(time * speeds[(index + 2) % speeds.count] * 0.53 + phases[(index + 1) % phases.count])
        let normalized = ((a + b) / 2 + 1) / 2
        return barWidth + CGFloat(normalized) * (maxHeight - barWidth)
    }
}

// MARK: - Battery glyph

/// An iOS-style battery outline with a proportional fill.
struct BatteryGlyph: View {
    var level: Int
    var color: Color
    var width: CGFloat = 25
    var height: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: height * 0.18, style: .continuous)
                    .fill(color)
                    .frame(width: max(2, (width - 4) * CGFloat(min(max(level, 0), 100)) / 100))
                    .padding(2)
            }
            .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1.5, height: height * 0.36)
        }
        .accessibilityLabel("Battery \(level) percent")
    }
}

// MARK: - Artwork

struct ArtworkView: View {
    var image: NSImage?
    var size: CGFloat
    var radius: CGFloat

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [Color(white: 0.28), Color(white: 0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.55))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Site icon

struct SiteIconView: View {
    var shortcut: WebShortcut
    var image: NSImage?
    var size: CGFloat

    var body: some View {
        ZStack {
            if let image {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color.white.opacity(0.94))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.16)
            } else {
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(Color.seeded(shortcut.host).gradient)
                Text(shortcut.monogram)
                    .font(.system(size: size * 0.46, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
        )
    }
}

// MARK: - Progress bar

struct ScrubBar: View {
    var progress: Double
    var isEnabled: Bool
    var onSeek: (Double) -> Void

    @State private var dragProgress: Double?
    @State private var isHovering = false

    var body: some View {
        GeometryReader { geometry in
            let value = min(max(dragProgress ?? progress, 0), 1)
            let active = isEnabled && (isHovering || dragProgress != nil)
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.2))
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .frame(width: max(0, geometry.size.width * value))
            }
            .frame(height: active ? 7 : 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard isEnabled, geometry.size.width > 0 else { return }
                        dragProgress = min(max(drag.location.x / geometry.size.width, 0), 1)
                    }
                    .onEnded { drag in
                        guard isEnabled, geometry.size.width > 0 else { return }
                        onSeek(min(max(drag.location.x / geometry.size.width, 0), 1))
                        dragProgress = nil
                    }
            )
            .onHover { isHovering = $0 }
            .animation(Theme.microSpring, value: active)
        }
        .frame(height: 12)
    }
}

// MARK: - Buttons

/// Glyph button with a soft circular highlight on hover and a springy press.
struct IslandButtonStyle: ButtonStyle {
    var diameter: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        IslandButtonBody(configuration: configuration, diameter: diameter)
    }
}

private struct IslandButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let diameter: CGFloat
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(Color.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(Color.white.opacity(configuration.isPressed ? 0.22 : (isHovering ? 0.12 : 0)))
            )
            .scaleEffect(configuration.isPressed ? 0.86 : 1)
            .contentShape(Circle())
            .onHover { isHovering = $0 }
            .animation(Theme.microSpring, value: isHovering)
            .animation(Theme.microSpring, value: configuration.isPressed)
    }
}

/// Capsule button used inside cards ("Open Music", "Add Sites").
struct CapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CapsuleButtonBody(configuration: configuration)
    }
}

private struct CapsuleButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.28 : (isHovering ? 0.2 : 0.13)))
            )
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .onHover { isHovering = $0 }
            .animation(Theme.microSpring, value: isHovering)
            .animation(Theme.microSpring, value: configuration.isPressed)
    }
}

// MARK: - Card

/// Translucent platter that holds one widget inside the expanded island.
struct WidgetCard<Content: View, Background: View>: View {
    let width: CGFloat
    let background: Background
    let content: Content

    init(width: CGFloat, @ViewBuilder background: () -> Background, @ViewBuilder content: () -> Content) {
        self.width = width
        self.background = background()
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(width: width, height: IslandMetrics.cardHeight, alignment: .topLeading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .fill(Theme.cardFill)
                    background
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Theme.cardStroke, Color.white.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.75
                    )
            )
    }
}

extension WidgetCard where Background == EmptyView {
    init(width: CGFloat, @ViewBuilder content: () -> Content) {
        self.init(width: width, background: { EmptyView() }, content: content)
    }
}
