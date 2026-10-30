import AppKit
import NotchCore
import SwiftUI

struct WebPagesCard: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var favicons: FaviconCache
    @State private var drag: TileDrag?

    struct TileDrag: Equatable {
        var id: UUID
        var pointer: CGPoint
        var grab: CGSize
    }

    private static let cell = CGSize(
        width: IslandMetrics.shortcutTileWidth + IslandMetrics.shortcutTileSpacing,
        height: 50 + 6
    )

    var body: some View {
        let shortcuts = settings.settings.shortcuts
        let columns = IslandMetrics.shortcutColumns(for: shortcuts.count)
        let width = IslandMetrics.cardWidth(for: .webPages, shortcutCount: shortcuts.count)
        let linkDrag = model.dragKind == .link

        WidgetCard(width: width) {
            if linkDrag {
                Theme.blue.opacity(model.isDropTargeted ? 0.28 : 0.14)
            }
        } content: {
            if linkDrag {
                dropPrompt
            } else if shortcuts.isEmpty {
                empty
            } else if shortcuts.count > columns * 2 && !model.isEditing {
                ScrollView(.vertical, showsIndicators: false) { grid(shortcuts, columns: columns) }
            } else {
                grid(shortcuts, columns: columns)
                    .frame(maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if model.isEditing && !linkDrag {
                Button {
                    model.addWebPage()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Theme.blue)
                        .font(.system(size: 20, weight: .semibold))
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .help("Add Web Page")
                .offset(x: 7, y: -7)
                .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .animation(Theme.openSpring, value: linkDrag)
    }

    private func grid(_ shortcuts: [WebShortcut], columns: Int) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.fixed(IslandMetrics.shortcutTileWidth), spacing: IslandMetrics.shortcutTileSpacing),
                count: columns
            ),
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(Array(shortcuts.enumerated()), id: \.element.id) { index, shortcut in
                let dragged = drag?.id == shortcut.id
                ShortcutTile(
                    shortcut: shortcut,
                    icon: favicons.icon(for: shortcut),
                    isEditing: model.isEditing,
                    open: { model.open(shortcut) },
                    remove: { model.removeShortcut(shortcut.id) },
                    edit: { model.openSettings(.webPages) }
                )
                .overlay {
                    if model.isEditing {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(reorderGesture(for: shortcut, columns: columns))
                    }
                }
                .overlay(alignment: .topLeading) {
                    if model.isEditing {
                        RemoveBadge(size: 15) { model.removeShortcut(shortcut.id) }
                            .offset(x: 1, y: -4)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .modifier(Wiggle(isActive: model.isEditing && !dragged, seed: Double(index) * 1.7))
                .scaleEffect(dragged ? 1.12 : 1)
                .offset(dragged ? tileOffset(index: index, columns: columns) : .zero)
                .zIndex(dragged ? 1 : 0)
            }
        }
        .coordinateSpace(name: "tiles")
    }

    private func origin(of index: Int, columns: Int) -> CGPoint {
        CGPoint(x: CGFloat(index % columns) * Self.cell.width, y: CGFloat(index / columns) * Self.cell.height)
    }

    private func tileOffset(index: Int, columns: Int) -> CGSize {
        guard let drag else { return .zero }
        let base = origin(of: index, columns: columns)
        return CGSize(width: drag.pointer.x - drag.grab.width - base.x, height: drag.pointer.y - drag.grab.height - base.y)
    }

    private func reorderGesture(for shortcut: WebShortcut, columns: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("tiles"))
            .onChanged { value in
                let shortcuts = settings.settings.shortcuts
                guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
                if drag?.id != shortcut.id {
                    let base = origin(of: index, columns: columns)
                    drag = TileDrag(
                        id: shortcut.id,
                        pointer: value.location,
                        grab: CGSize(width: value.startLocation.x - base.x, height: value.startLocation.y - base.y)
                    )
                    model.beginDragOut()
                }
                drag?.pointer = value.location

                let rows = max(1, Int((Double(shortcuts.count) / Double(columns)).rounded(.up)))
                let column = min(max(Int(value.location.x / Self.cell.width), 0), columns - 1)
                let row = min(max(Int(value.location.y / Self.cell.height), 0), rows - 1)
                model.moveShortcut(shortcut.id, to: min(row * columns + column, shortcuts.count - 1))
            }
            .onEnded { _ in
                withAnimation(Theme.openSpring) { drag = nil }
            }
    }

    private var dropPrompt: some View {
        VStack(spacing: 6) {
            Image(systemName: model.isDropTargeted ? "link.badge.plus" : "link")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(model.isDropTargeted ? Theme.blue : Theme.secondary)
                .symbolEffect(.bounce, value: model.isDropTargeted)
            Text(model.isDropTargeted ? "Drop to save" : "Save this link")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.isDropTargeted ? Color.white : Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    model.isDropTargeted ? Theme.blue : Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
        )
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "globe")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text("No web pages yet")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Text("Drag a link onto the notch")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
            Spacer(minLength: 0)
            Button("Add Sites") { model.addWebPage() }
                .buttonStyle(CapsuleButtonStyle())
        }
    }
}

private struct ShortcutTile: View {
    let shortcut: WebShortcut
    let icon: SiteIcon?
    let isEditing: Bool
    let open: () -> Void
    let remove: () -> Void
    let edit: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: open) {
            VStack(spacing: 4) {
                SiteIconView(shortcut: shortcut, icon: icon, size: 34)
                    .scaleEffect(isHovering && !isEditing ? 1.1 : 1)
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
