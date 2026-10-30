import AppKit
import NotchCore
import SwiftUI

struct WebPagesCard: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var favicons: FaviconCache

    var body: some View {
        let shortcuts = settings.settings.shortcuts
        let columns = IslandMetrics.shortcutColumns(for: shortcuts.count)
        let width = IslandMetrics.cardWidth(for: .webPages, shortcutCount: shortcuts.count)

        WidgetCard(width: width) {
            if shortcuts.isEmpty {
                empty
            } else {
                let grid = LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(IslandMetrics.shortcutTileWidth), spacing: IslandMetrics.shortcutTileSpacing),
                        count: columns
                    ),
                    spacing: 6
                ) {
                    ForEach(shortcuts) { shortcut in
                        ShortcutTile(
                            shortcut: shortcut,
                            icon: favicons.image(for: shortcut),
                            open: { model.open(shortcut) },
                            remove: { settings.removeShortcut(id: shortcut.id) },
                            edit: { model.openSettings(.webPages) }
                        )
                    }
                }
                if shortcuts.count > columns * 2 {
                    ScrollView(.vertical, showsIndicators: false) { grid }
                } else {
                    grid
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text("No web pages yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button("Add Sites") { model.openSettings(.webPages) }
                .buttonStyle(CapsuleButtonStyle())
        }
    }
}

private struct ShortcutTile: View {
    let shortcut: WebShortcut
    let icon: NSImage?
    let open: () -> Void
    let remove: () -> Void
    let edit: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 4) {
                SiteIconView(shortcut: shortcut, image: icon, size: 36)
                    .scaleEffect(isHovering ? 1.08 : 1)
                    .shadow(color: .black.opacity(isHovering ? 0.35 : 0.15), radius: isHovering ? 6 : 2, y: 2)
                Text(shortcut.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(isHovering ? Color.white : Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: IslandMetrics.shortcutTileWidth)
            }
            .frame(width: IslandMetrics.shortcutTileWidth, height: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(Theme.microSpring, value: isHovering)
        .help(shortcut.url.absoluteString)
        .contextMenu {
            Button("Open \(shortcut.name)", action: open)
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(shortcut.url.absoluteString, forType: .string)
            }
            Divider()
            Button("Edit Web Pages…", action: edit)
            Button("Remove \(shortcut.name)", role: .destructive, action: remove)
        }
    }
}
