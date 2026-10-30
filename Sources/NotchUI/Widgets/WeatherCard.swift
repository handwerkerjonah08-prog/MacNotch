import NotchCore
import SwiftUI

struct WeatherCard: View {
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var settings: SettingsModel

    var body: some View {
        WidgetCard(width: IslandMetrics.cardWidth(for: .weather, shortcutCount: 0)) {
            sky
        } content: {
            Group {
                if let snapshot = weather.snapshot {
                    conditions(snapshot)
                } else if weather.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    unavailable
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { weather.openWeatherApp() }
        .help("Open Weather")
    }

    private func conditions(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 3) {
                Text(settings.settings.weatherLocation.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Image(systemName: "location.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(snapshot.temperatureText)
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .padding(.top, -2)
            Spacer(minLength: 0)
            Image(systemName: snapshot.condition.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 14))
                .padding(.bottom, 2)
            Text(snapshot.condition.description)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(snapshot.highLowText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut, value: snapshot.temperatureText)
    }

    private var unavailable: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "cloud.fill")
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 22))
            Text(weather.errorMessage ?? "Weather unavailable")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button("Retry") { weather.refresh() }
                .buttonStyle(CapsuleButtonStyle())
        }
    }

    /// Apple Weather style sky, dimmed so it sits inside the dark island.
    private var sky: some View {
        let category = weather.snapshot?.condition.category ?? .unknown
        let isDay = weather.snapshot?.isDay ?? true
        return LinearGradient(colors: Self.skyColors(category: category, isDay: isDay), startPoint: .top, endPoint: .bottom)
            .opacity(0.55)
    }

    static func skyColors(category: WeatherCategory, isDay: Bool) -> [Color] {
        guard isDay else {
            switch category {
            case .clear, .partlyCloudy:
                return [Color(red: 0.05, green: 0.09, blue: 0.27), Color(red: 0.12, green: 0.2, blue: 0.45)]
            case .rain, .drizzle, .storm:
                return [Color(red: 0.08, green: 0.1, blue: 0.16), Color(red: 0.2, green: 0.24, blue: 0.32)]
            default:
                return [Color(red: 0.1, green: 0.12, blue: 0.2), Color(red: 0.24, green: 0.27, blue: 0.36)]
            }
        }
        switch category {
        case .clear:
            return [Color(red: 0.16, green: 0.45, blue: 0.86), Color(red: 0.38, green: 0.68, blue: 0.96)]
        case .partlyCloudy:
            return [Color(red: 0.22, green: 0.44, blue: 0.74), Color(red: 0.46, green: 0.62, blue: 0.82)]
        case .cloudy, .fog:
            return [Color(red: 0.33, green: 0.4, blue: 0.5), Color(red: 0.5, green: 0.56, blue: 0.64)]
        case .rain, .drizzle:
            return [Color(red: 0.2, green: 0.27, blue: 0.38), Color(red: 0.36, green: 0.43, blue: 0.53)]
        case .snow:
            return [Color(red: 0.45, green: 0.52, blue: 0.62), Color(red: 0.66, green: 0.72, blue: 0.8)]
        case .storm:
            return [Color(red: 0.14, green: 0.15, blue: 0.24), Color(red: 0.3, green: 0.3, blue: 0.42)]
        case .unknown:
            return [Color(red: 0.2, green: 0.3, blue: 0.5), Color(red: 0.3, green: 0.4, blue: 0.6)]
        }
    }
}
