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
            Color.clear
                .glassEffect(.regular.tint(Color.black.opacity(0.22 + 0.68 * tint)), in: shape)
        } else {
            FallbackGlass(shape: shape, tint: tint)
        }
        #else
        FallbackGlass(shape: shape, tint: tint)
        #endif
    }
}

/// Drawn glass for macOS 14-15 and for snapshot rendering.
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
