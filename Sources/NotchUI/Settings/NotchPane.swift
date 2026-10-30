import NotchCore
import SwiftUI

/// Choose what sits beside the notch, with a live preview.
struct NotchPane: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .notch, subtitle: "Choose what sits beside the notch while the island is closed, like the iPhone's compact Live Activities.")
            }

            Section {
                NotchPreview()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                Picker(selection: $model.settings.notchLeading) {
                    slotOptions
                } label: {
                    Label("Left of the notch", systemImage: "rectangle.lefthalf.inset.filled")
                }
                Picker(selection: $model.settings.notchTrailing) {
                    slotOptions
                } label: {
                    Label("Right of the notch", systemImage: "rectangle.righthalf.inset.filled")
                }
            } header: {
                Text("Beside the Notch")
            } footer: {
                Text("Choose Nothing on both sides to keep the notch plain. Music and alerts take over this space while they're showing.")
            }

            Section {
                Toggle("Show what's playing in Apple Music", isOn: $model.settings.showNowPlayingActivity)
                Toggle("Charging alerts", isOn: $model.settings.chargingAlerts)
                Toggle("Low battery alerts at 20% and 10%", isOn: $model.settings.lowBatteryAlerts)
            } header: {
                Text("Live Activities")
            } footer: {
                Text("These appear beside the notch on their own, without opening the island.")
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var slotOptions: some View {
        ForEach(NotchSlot.allCases) { slot in
            Label(slot.title, systemImage: slot.symbolName).tag(slot)
        }
    }
}

/// A slice of the MacBook screen showing the closed island with the chosen items.
struct NotchPreview: View {
    @EnvironmentObject private var model: SettingsModel

    private let notch = CGSize(width: 150, height: 32)

    var body: some View {
        let current = model.settings
        let presentation: IslandPresentation = current.showsNotchInfo ? .compactInfo : .idle
        let size = IslandMetrics.size(
            for: presentation, notch: notch, widgets: [], shortcutCount: 0, maxWidth: 600,
            leading: current.notchLeading, trailing: current.notchTrailing
        )
        let radii = IslandMetrics.radii(for: presentation)

        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.86, green: 0.55, blue: 0.95), Color(red: 0.5, green: 0.2, blue: 0.85), Color(red: 0.16, green: 0.06, blue: 0.36)],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack {
                Image(systemName: "apple.logo")
                Text("Finder").fontWeight(.bold)
                Spacer()
                Image(systemName: "wifi")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .frame(height: notch.height)

            ZStack {
                NotchShape(topRadius: radii.top, bottomRadius: radii.bottom)
                    .fill(Color.black)
                if presentation == .compactInfo {
                    CompactInfoView(notch: notch)
                        .padding(.horizontal, radii.top)
                        .transition(.islandContent)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(width: 460, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .animation(Theme.openSpring, value: current.notchLeading)
        .animation(Theme.openSpring, value: current.notchTrailing)
    }
}
