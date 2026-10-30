import AppKit
import SwiftUI

/// Diagnostic panel for CI: the same non-key window type as the island, showing several glass
/// techniques side by side over a colorful backdrop, so screenshots show which ones are see-through.
@MainActor
enum GlassLab {
    static func show(on screen: NSScreen) -> NSPanel {
        let panel = NotchPanel.make()
        panel.ignoresMouseEvents = true
        let size = CGSize(width: 980, height: 190)
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY + 150)
        panel.setFrame(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height), display: true)
        let host = NSHostingView(rootView: GlassLabView())
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        return panel
    }
}

private struct GlassLabView: View {
    var body: some View {
        HStack(spacing: 14) {
            tile("A swiftui") { swiftUIGlass(activeKey: false) }
            tile("B swiftui+key") { swiftUIGlass(activeKey: true) }
            tile("C vibrancy") {
                VisualEffectBackground(material: .hudWindow)
                    .clipShape(NotchShape(topRadius: 14, bottomRadius: 30))
            }
            tile("D appkit glass") {
                AppKitGlassBackground(cornerRadius: 30)
                    .clipShape(NotchShape(topRadius: 14, bottomRadius: 30))
            }
            tile("E material") {
                NotchShape(topRadius: 14, bottomRadius: 30).fill(.ultraThinMaterial)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }

    private func tile<Background: View>(_ label: String, @ViewBuilder background: () -> Background) -> some View {
        ZStack {
            background()
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 176, height: 160)
    }

    @ViewBuilder
    private func swiftUIGlass(activeKey: Bool) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            if activeKey {
                Color.clear
                    .glassEffect(.regular, in: NotchShape(topRadius: 14, bottomRadius: 30))
                    .environment(\.controlActiveState, .key)
            } else {
                Color.clear
                    .glassEffect(.regular, in: NotchShape(topRadius: 14, bottomRadius: 30))
            }
        } else {
            Color.red
        }
        #else
        Color.red
        #endif
    }
}

/// macOS 26's AppKit Liquid Glass view, looked up at run time so older SDKs still build.
struct AppKitGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        guard let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type else {
            let fallback = NSView()
            fallback.wantsLayer = true
            fallback.layer?.backgroundColor = NSColor.systemRed.cgColor
            return fallback
        }
        let view = glassClass.init(frame: .zero)
        if view.responds(to: NSSelectorFromString("setCornerRadius:")) {
            view.setValue(cornerRadius, forKey: "cornerRadius")
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}
