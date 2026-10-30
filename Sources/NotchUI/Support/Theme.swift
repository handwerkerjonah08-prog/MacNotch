import NotchCore
import SwiftUI

enum Theme {
    static let primary = Color.white
    static let secondary = Color.white.opacity(0.62)
    static let tertiary = Color.white.opacity(0.36)
    static let cardFill = Color.white.opacity(0.075)
    static let cardStroke = Color.white.opacity(0.09)
    static let cardRadius: CGFloat = 18

    /// Opening overshoots a touch, like the iPhone island.
    static let openSpring = Animation.spring(response: 0.46, dampingFraction: 0.74)
    /// Closing settles quickly without bounce.
    static let closeSpring = Animation.spring(response: 0.36, dampingFraction: 0.9)
    static let microSpring = Animation.spring(response: 0.28, dampingFraction: 0.7)
}

/// Blur + fade used for content entering and leaving the island.
private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

extension AnyTransition {
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: BlurFade(radius: 10, opacity: 0),
                identity: BlurFade(radius: 0, opacity: 1)
            )
            .combined(with: .scale(scale: 0.88, anchor: .top))
            .animation(Theme.openSpring.delay(0.06)),
            removal: .modifier(
                active: BlurFade(radius: 6, opacity: 0),
                identity: BlurFade(radius: 0, opacity: 1)
            )
            .animation(.easeOut(duration: 0.14))
        )
    }

    static var wingContent: AnyTransition {
        .modifier(
            active: BlurFade(radius: 6, opacity: 0),
            identity: BlurFade(radius: 0, opacity: 1)
        )
        .combined(with: .scale(scale: 0.6))
    }
}

// MARK: - Environment

private struct ForceGlassFallbackKey: EnvironmentKey {
    static let defaultValue = false
}

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering PNG snapshots, so views can skip AppKit-backed modifiers.
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }

    /// ImageRenderer can't draw real Liquid Glass, so snapshots use the drawn approximation.
    var forceGlassFallback: Bool {
        get { self[ForceGlassFallbackKey.self] }
        set { self[ForceGlassFallbackKey.self] = newValue }
    }
}

extension Color {
    init(rgb: RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// Deterministic pleasant color for a string, used for monogram tiles.
    static func seeded(_ seed: String) -> Color {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.78)
    }
}
