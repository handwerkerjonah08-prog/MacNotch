import AppKit
import NotchCore
import SwiftUI

/// System Settings style window: colored icon sidebar on the left, grouped form on the right.
struct SettingsRootView: View {
    @ObservedObject var router: SettingsRouter
    let island: IslandViewModel

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $router.selection) { pane in
                Label {
                    Text(pane.title)
                } icon: {
                    SettingsIcon(symbol: pane.symbol, color: pane.color)
                }
                .tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 260)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            let pane = router.selection ?? .general
            detail(for: pane)
                .navigationTitle(pane.title)
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 700, minHeight: 480)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func detail(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane(island: island)
        case .notch: NotchPane()
        case .appearance: AppearancePane(island: island)
        case .widgets: WidgetsPane()
        case .webPages: WebPagesPane()
        case .weather: WeatherPane()
        case .shelf: ShelfPane()
        case .about: AboutPane()
        }
    }
}

struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(color.gradient)
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Header shown at the top of each pane, like System Settings.
struct PaneHeader: View {
    let pane: SettingsPane
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            SettingsIcon(symbol: pane.symbol, color: pane.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(pane.title)
                    .font(.system(size: 17, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }
}
