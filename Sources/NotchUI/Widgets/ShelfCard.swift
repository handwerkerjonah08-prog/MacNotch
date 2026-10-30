import AppKit
import NotchCore
import SwiftUI

struct ShelfCard: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var shelf: ShelfModel

    var body: some View {
        let fileDrag = model.dragKind == .file
        let targeted = fileDrag && model.isDropTargeted
        WidgetCard(width: IslandMetrics.cardWidth(for: .fileShelf, shortcutCount: 0)) {
            if targeted {
                Theme.blue.opacity(0.18)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    Text("Shelf")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    if !shelf.items.isEmpty {
                        Text("\(shelf.items.count)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.tertiary)
                    }
                    Spacer(minLength: 0)
                    if !shelf.items.isEmpty {
                        Button {
                            withAnimation(Theme.openSpring) { shelf.clear() }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .buttonStyle(IslandButtonStyle(diameter: 20))
                        .help("Clear Shelf")
                    }
                }

                if shelf.items.isEmpty || fileDrag {
                    dropZone(targeted: targeted)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(shelf.items) { item in
                                ShelfItemView(
                                    item: item,
                                    icon: shelf.icon(for: item),
                                    provider: {
                                        model.beginDragOut()
                                        return shelf.dragProvider(for: item)
                                    },
                                    open: { shelf.open(item) },
                                    reveal: { shelf.reveal(item) },
                                    remove: { withAnimation(Theme.openSpring) { shelf.remove(item) } }
                                )
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
        .animation(Theme.openSpring, value: targeted)
        .animation(Theme.openSpring, value: shelf.items.map(\.id))
    }

    private func dropZone(targeted: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(targeted ? Theme.blue : Theme.secondary)
                .symbolEffect(.bounce, value: targeted)
            Text(targeted ? "Drop to add" : "Drop files here")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(targeted ? Color.white : Theme.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    targeted ? Theme.blue : Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
        )
        .scaleEffect(targeted ? 1.03 : 1)
    }
}

private struct ShelfItemView: View {
    let item: ShelfItem
    let icon: NSImage
    let provider: () -> NSItemProvider
    let open: () -> Void
    let reveal: () -> Void
    let remove: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            Text(item.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(isHovering ? Color.white : Theme.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 54, height: 24, alignment: .top)
        }
        .frame(width: 56)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovering ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(action: remove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                        .font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .animation(Theme.microSpring, value: isHovering)
        .onTapGesture(count: 2, perform: open)
        .onDrag(provider)
        .help(item.path)
        .contextMenu {
            Button("Open", action: open)
            Button("Show in Finder", action: reveal)
            Divider()
            Button("Remove from Shelf", role: .destructive, action: remove)
        }
    }
}
