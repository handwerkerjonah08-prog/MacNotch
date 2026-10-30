import AppKit
import SwiftUI

enum LiquidGlass {
    /// Real Liquid Glass needs the macOS 26 SDK at build time and macOS 26+ at run time.
    static var isSupported: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            return true
        }
        #endif
        return false
    }
}

/// The island's glass body. Uses system Liquid Glass when available, otherwise a drawn approximation.
struct GlassFill<S: Shape>: View {
    let shape: S
    /// 0 = ultra clear, 1 = fully tinted.
    let tint: Double
    @Environment(\.forceGlassFallback) private var forceFallback

    var body: some View {
        if forceFallback {
            FallbackGlass(shape: shape, tint: tint)
        } else {
            systemGlass
        }
    }

    @ViewBuilder
    private var systemGlass: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            ZStack {
                Color.clear
                    .glassEffect(.regular.tint(Color.black.opacity(0.2 + 0.4 * tint)), in: shape)
                // System glass tint is only a hint, so the slider also darkens the pane directly.
                shape.fill(Color.black.opacity(0.62 * tint))
            }
        } else {
            BlurGlass(shape: shape, tint: tint)
        }
        #else
        BlurGlass(shape: shape, tint: tint)
        #endif
    }
}

/// macOS 14-15: a behind-window blur pinned to its active look, since the island's window is never key.
struct BlurGlass<S: Shape>: View {
    let shape: S
    let tint: Double

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)
            Color(white: 0.04).opacity(0.25 + 0.55 * tint)
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .clipShape(shape)
    }
}

/// Drawn glass for snapshot rendering and the Settings previews.
struct FallbackGlass<S: Shape>: View {
    let shape: S
    let tint: Double

    var body: some View {
        ZStack {
            shape.fill(.ultraThinMaterial)
            shape.fill(Color(white: 0.06).opacity(0.42 + 0.5 * tint))
            // Soft specular sheen across the top, like light hitting a curved pane.
            shape.fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.02), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }
}

/// Bright rim highlight that fades in toward the bottom edge (iOS 27 brightened specular edges).
struct SpecularRim<S: Shape>: View {
    let shape: S
    /// Fraction of the height (from the top) that stays free of highlight, e.g. the notch band.
    let clearFraction: CGFloat

    var body: some View {
        shape.stroke(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .clear, location: clearFraction),
                    .init(color: Color.white.opacity(0.10), location: min(1, clearFraction + 0.25)),
                    .init(color: Color.white.opacity(0.32), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1.2
        )
    }
}

extension View {
    /// Liquid Glass button style on macOS 26+, bordered elsewhere.
    @ViewBuilder
    func glassButtonStyle(prominent: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
        #else
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
        #endif
    }
}

/// NSVisualEffectView forced into its active look, so it keeps blurring in a window that is never key.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
