import NotchCore
import SwiftUI

/// The expanded island: a header beside the notch and a row of widget cards underneath.
struct ExpandedIslandView: View {
    @ObservedObject var model: IslandViewModel
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var battery: BatteryMonitor

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

    private func cardsRow(_ widgets: [WidgetKind]) -> some View {
        HStack(spacing: IslandMetrics.cardSpacing) {
            ForEach(widgets) { kind in
                card(for: kind)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
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

    private func header(notch: CGSize) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                TimelineView(.everyMinute) { context in
                    Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 6)

            Color.clear.frame(width: notch.width)

            HStack(spacing: 8) {
                if let power = battery.snapshot {
                    HStack(spacing: 4) {
                        if power.isCharging {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.2, green: 0.84, blue: 0.29))
                        }
                        Text("\(power.level)%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Theme.secondary)
                        BatteryGlyph(
                            level: power.level,
                            color: power.isCharging
                                ? Color(red: 0.2, green: 0.84, blue: 0.29)
                                : (power.level <= 20 ? Color(red: 1, green: 0.27, blue: 0.23) : Color.white.opacity(0.85)),
                            width: 22,
                            height: 11
                        )
                    }
                }
                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(IslandButtonStyle(diameter: 26))
                .help("MacNotch Settings")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 2)
        }
        .padding(.horizontal, IslandMetrics.contentPadding)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.secondary)
            Text("No widgets turned on")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Button("Choose Widgets") { model.openSettings(.widgets) }
                .buttonStyle(CapsuleButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
