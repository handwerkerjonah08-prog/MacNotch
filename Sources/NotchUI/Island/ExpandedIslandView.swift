import NotchCore
import SwiftUI

/// The expanded island: a header beside the notch and a row of widget cards underneath.
/// In edit mode the cards wiggle like iPhone's home screen and can be dragged, removed or added.
struct ExpandedIslandView: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var battery: BatteryMonitor
    @State private var drag: CardDrag?

    /// A card being dragged: where the pointer is, and where on the card it was grabbed.
    struct CardDrag: Equatable {
        var kind: WidgetKind
        var pointerX: CGFloat
        var grabOffset: CGFloat
    }

    var body: some View {
        let notch = model.notch.size
        let widgets = settings.settings.enabledWidgetKinds
        let shortcutCount = settings.settings.shortcuts.count
        let rowWidth = IslandMetrics.cardsRowWidth(widgets: widgets, shortcutCount: shortcutCount)
        let available = model.islandSize.width
            - IslandMetrics.radii(for: .expanded).top * 2
            - IslandMetrics.contentPadding * 2

        VStack(spacing: 0) {
            header(notch: notch)
                .frame(height: notch.height)

            Spacer().frame(height: IslandMetrics.headerGap)

            Group {
                if widgets.isEmpty {
                    emptyState
                } else if rowWidth <= available + 0.5 {
                    cardsRow(widgets)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        cardsRow(widgets)
                    }
                }
            }
            .frame(height: IslandMetrics.cardHeight)
            .padding(.horizontal, IslandMetrics.contentPadding)

            Spacer().frame(height: IslandMetrics.bottomPadding)
        }
    }

    // MARK: Cards

    private func cardsRow(_ widgets: [WidgetKind]) -> some View {
        HStack(spacing: IslandMetrics.cardSpacing) {
            ForEach(widgets) { kind in
                let dragged = drag?.kind == kind
                card(for: kind)
                    .overlay {
                        if model.isEditing {
                            Color.clear
                                .contentShape(Rectangle())
                                .gesture(reorderGesture(for: kind, in: widgets))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if model.isEditing {
                            RemoveBadge { model.removeWidget(kind) }
                                .offset(x: -7, y: -7)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
                    .modifier(Wiggle(isActive: model.isEditing && !dragged, seed: Double(kind.hashValue % 97)))
                    .scaleEffect(dragged ? 1.05 : 1)
                    .shadow(color: .black.opacity(dragged ? 0.45 : 0), radius: dragged ? 14 : 0, y: dragged ? 8 : 0)
                    .offset(x: dragged ? dragOffset(for: kind, in: widgets) : 0)
                    .zIndex(dragged ? 1 : 0)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "cards")
    }

    @ViewBuilder
    private func card(for kind: WidgetKind) -> some View {
        switch kind {
        case .nowPlaying:
            NowPlayingCard()
        case .weather:
            WeatherCard()
        case .webPages:
            WebPagesCard(model: model)
        case .fileShelf:
            ShelfCard(model: model)
        }
    }

    // MARK: Reordering

    private func cardWidth(_ kind: WidgetKind) -> CGFloat {
        IslandMetrics.cardWidth(for: kind, shortcutCount: settings.settings.shortcuts.count)
    }

    /// Leading edge of each card in the row's coordinate space, for the current order.
    private func layoutX(of kind: WidgetKind, in widgets: [WidgetKind]) -> CGFloat {
        var x: CGFloat = 0
        for item in widgets {
            if item == kind { return x }
            x += cardWidth(item) + IslandMetrics.cardSpacing
        }
        return x
    }

    private func dragOffset(for kind: WidgetKind, in widgets: [WidgetKind]) -> CGFloat {
        guard let drag, drag.kind == kind else { return 0 }
        return drag.pointerX - drag.grabOffset - layoutX(of: kind, in: widgets)
    }

    private func reorderGesture(for kind: WidgetKind, in widgets: [WidgetKind]) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("cards"))
            .onChanged { value in
                let order = settings.settings.enabledWidgetKinds
                if drag?.kind != kind {
                    drag = CardDrag(
                        kind: kind,
                        pointerX: value.location.x,
                        grabOffset: value.startLocation.x - layoutX(of: kind, in: order)
                    )
                    model.beginDragOut()
                }
                drag?.pointerX = value.location.x

                // Slot the card in front of every card whose center it has passed.
                let center = value.location.x - (drag?.grabOffset ?? 0) + cardWidth(kind) / 2
                let others = order.filter { $0 != kind }
                let target = others.filter { layoutX(of: $0, in: order) + cardWidth($0) / 2 < center }.count
                model.moveWidget(kind, toVisibleIndex: target)
            }
            .onEnded { _ in
                withAnimation(Theme.openSpring) { drag = nil }
            }
    }

    // MARK: Header

    @ViewBuilder
    private func header(notch: CGSize) -> some View {
        HStack(spacing: 0) {
            Group {
                if model.isEditing {
                    addWidgetMenu
                } else {
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)

            Color.clear.frame(width: notch.width)

            Group {
                if model.isEditing {
                    Button("Done") { model.endEditing() }
                        .buttonStyle(CapsuleButtonStyle(prominent: true))
                } else {
                    HStack(spacing: 8) {
                        if let power = battery.snapshot {
                            HStack(spacing: 4) {
                                if power.isCharging {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Theme.green)
                                }
                                Text("\(power.level)%")
                                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Theme.secondary)
                                BatteryGlyph(
                                    level: power.level,
                                    color: Theme.batteryColor(level: power.level, charging: power.isCharging),
                                    width: 22,
                                    height: 11
                                )
                            }
                        }
                        Button {
                            model.beginEditing()
                        } label: {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(IslandButtonStyle(diameter: 26))
                        .help("Edit Widgets")
                        Button {
                            model.openSettings()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(IslandButtonStyle(diameter: 26))
                        .help("MacNotch Settings")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 2)
        }
        .padding(.horizontal, IslandMetrics.contentPadding)
    }

    @ViewBuilder
    private var addWidgetMenu: some View {
        let hidden = settings.settings.disabledWidgetKinds
        if hidden.isEmpty {
            Text("Drag to rearrange")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        } else {
            Menu {
                ForEach(hidden) { kind in
                    Button {
                        model.addWidget(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbolName)
                    }
                }
            } label: {
                Label("Add Widget", systemImage: "plus")
            }
            .menuStyle(.button)
            .buttonStyle(CapsuleButtonStyle())
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text("No widgets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            if model.isEditing {
                Text("Use Add Widget to bring one back.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondary)
            } else {
                Button("Edit Widgets") { model.beginEditing() }
                    .buttonStyle(CapsuleButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The minus button on a wiggling card or icon.
struct RemoveBadge: View {
    var size: CGFloat = 20
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.black, Color.white.opacity(0.92))
                .font(.system(size: size, weight: .semibold))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .help("Remove")
    }
}

/// iPhone home screen edit-mode wiggle. A repeating animation, so SwiftUI only interpolates the angle
/// instead of rebuilding the card every frame.
struct Wiggle: ViewModifier {
    let isActive: Bool
    let seed: Double
    @State private var tilted = false

    private var duration: Double {
        0.12 + abs(seed).truncatingRemainder(dividingBy: 5) * 0.008
    }

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isActive ? (tilted ? 1.1 : -1.1) : 0))
            .animation(
                isActive ? .easeInOut(duration: duration).repeatForever(autoreverses: true) : .easeOut(duration: 0.15),
                value: tilted
            )
            .onAppear {
                if isActive { tilted.toggle() }
            }
            .onChange(of: isActive) { _, active in
                tilted = active ? !tilted : false
            }
    }
}
