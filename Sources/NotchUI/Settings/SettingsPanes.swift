import AppKit
import NotchCore
import SwiftUI

// MARK: - General

struct GeneralPane: View {
    let island: IslandViewModel
    @EnvironmentObject private var model: SettingsModel
    @State private var launchStatus = LaunchAtLogin.status
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .general, subtitle: "MacNotch turns your notch into a Dynamic Island. Hover over the notch to open it.")
            }

            Section("Behavior") {
                Toggle("Open MacNotch at login", isOn: launchBinding)
                if launchStatus == .requiresApproval {
                    HStack {
                        Text("Approve MacNotch in Login Items to finish.")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items") { LaunchAtLogin.openLoginItemsSettings() }
                    }
                }
                if let launchError {
                    Text(launchError)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                Picker("Open the island with", selection: $model.settings.expandTrigger) {
                    ForEach(ExpandTrigger.allCases) { trigger in
                        Text(trigger.title).tag(trigger)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Haptic feedback when it opens", isOn: $model.settings.hapticsEnabled)
                Toggle("Show icon in menu bar", isOn: $model.settings.showMenuBarIcon)
            }

            Section {
                Button {
                    island.beginEditing()
                } label: {
                    Label("Edit Widgets in the Island", systemImage: "square.grid.2x2")
                }
                .glassButtonStyle()
            } footer: {
                Text("Choose what shows beside the notch in the Notch section.")
            }
        }
        .formStyle(.grouped)
        .onAppear { launchStatus = LaunchAtLogin.status }
    }

    private var launchBinding: Binding<Bool> {
        Binding(
            get: { launchStatus == .enabled || launchStatus == .requiresApproval },
            set: { enabled in
                do {
                    try LaunchAtLogin.setEnabled(enabled)
                    launchError = nil
                } catch {
                    launchError = "Couldn't update the login item. Make sure MacNotch is in your Applications folder, then try again."
                }
                launchStatus = LaunchAtLogin.status
            }
        )
    }
}

// MARK: - Appearance

struct AppearancePane: View {
    let island: IslandViewModel
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .appearance, subtitle: "Choose how the island looks when it opens. It always stays black over the notch so the camera cutout disappears.")
            }

            Section("Island Style") {
                HStack(spacing: 18) {
                    ForEach(IslandMaterial.allCases) { material in
                        StyleOption(
                            material: material,
                            tint: model.settings.glassTint,
                            isSelected: model.settings.islandMaterial == material
                        ) {
                            withAnimation(Theme.openSpring) { model.settings.islandMaterial = material }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)

                if model.settings.islandMaterial == .liquidGlass {
                    Slider(value: $model.settings.glassTint, in: 0...1) {
                        Text("Glass")
                    } minimumValueLabel: {
                        Text("Clear").font(.caption)
                    } maximumValueLabel: {
                        Text("Tinted").font(.caption)
                    }
                    if !LiquidGlass.isSupported {
                        Text("Real Liquid Glass needs macOS 26 or later, so you'll see a close match instead.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    island.previewExpanded(seconds: 4)
                } label: {
                    Label("Preview the Island", systemImage: "sparkles")
                }
                .glassButtonStyle()
            } footer: {
                Text("Opens the island for a few seconds so you can see your changes.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct StyleOption: View {
    let material: IslandMaterial
    let tint: Double
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 8) {
                ZStack(alignment: .top) {
                    LinearGradient(
                        colors: [Color(red: 0.86, green: 0.55, blue: 0.95), Color(red: 0.42, green: 0.16, blue: 0.75), Color(red: 0.12, green: 0.04, blue: 0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    miniIsland
                }
                .frame(width: 168, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 3 : 1)
                )
                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(material.title)
                        .font(.system(size: 12, weight: .medium))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var miniIsland: some View {
        let shape = NotchShape(topRadius: 6, bottomRadius: 14)
        return ZStack {
            if material == .liquidGlass {
                FallbackGlass(shape: shape, tint: tint)
                shape.fill(
                    LinearGradient(
                        stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.18), .init(color: .clear, location: 0.5)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                SpecularRim(shape: shape, clearFraction: 0.2)
            } else {
                shape.fill(Color.black)
            }
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 30, height: 28)
                }
            }
            .padding(.top, 14)
        }
        .frame(width: 124, height: 56)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Widgets

struct WidgetsPane: View {
    @EnvironmentObject private var model: SettingsModel

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .widgets, subtitle: "Pick which widgets appear in the island and put them in the order you like.")
            }

            Section {
                ForEach($model.settings.widgets) { $widget in
                    WidgetRow(
                        widget: $widget,
                        isFirst: model.settings.widgets.first?.kind == widget.kind,
                        isLast: model.settings.widgets.last?.kind == widget.kind,
                        move: { offset in
                            withAnimation { model.moveWidget(widget.kind, by: offset) }
                        }
                    )
                }
                .onMove { source, destination in
                    model.moveWidgets(from: source, to: destination)
                }
            } header: {
                Text("Widgets")
            } footer: {
                Text("Widgets show left to right in this order. Drag a row or use the arrows to reorder.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct WidgetRow: View {
    @Binding var widget: WidgetConfig
    let isFirst: Bool
    let isLast: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: widget.kind.symbolName, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(widget.kind.title)
                Text(widget.kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(isFirst)
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(isLast)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            Toggle("Show \(widget.kind.title)", isOn: $widget.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.vertical, 2)
    }

    private var color: Color {
        switch widget.kind {
        case .nowPlaying: return Color(red: 0.98, green: 0.24, blue: 0.35)
        case .weather: return Color(red: 0.2, green: 0.7, blue: 0.95)
        case .webPages: return Color(red: 0.35, green: 0.35, blue: 0.85)
        case .fileShelf: return Color(red: 1, green: 0.6, blue: 0.1)
        }
    }
}

// MARK: - Weather

struct WeatherPane: View {
    @EnvironmentObject private var model: SettingsModel
    @EnvironmentObject private var weather: WeatherService
    @State private var query = ""
    @State private var results: [WeatherLocation] = []
    @State private var isSearching = false
    @State private var searchMessage: String?

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .weather, subtitle: "Current conditions for any city, refreshed every 15 minutes.")
            }

            Section("Location") {
                LabeledContent("Showing weather for") {
                    Text(model.settings.weatherLocation.displayName)
                        .foregroundStyle(.secondary)
                }
                TextField(text: $query, prompt: Text("Search for a city")) {
                    Text("Change location")
                }
                if isSearching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Searching…").foregroundStyle(.secondary)
                    }
                }
                if let searchMessage {
                    Text(searchMessage).foregroundStyle(.secondary)
                }
                ForEach(results, id: \.self) { location in
                    Button {
                        select(location)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(location.name)
                                if !location.region.isEmpty {
                                    Text(location.region)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Units") {
                Picker("Temperature", selection: $model.settings.temperatureUnit) {
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                }
            }

            Section {
                HStack(spacing: 8) {
                    if let snapshot = weather.snapshot {
                        Image(systemName: snapshot.condition.symbolName)
                            .symbolRenderingMode(.multicolor)
                        Text("\(snapshot.temperatureText) and \(snapshot.condition.description.lowercased())")
                        Text("Updated \(Text(snapshot.fetchedAt, style: .relative)) ago")
                            .foregroundStyle(.secondary)
                    } else if let error = weather.errorMessage {
                        Text(error).foregroundStyle(.secondary)
                    } else {
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Refresh") { weather.refresh() }
                        .disabled(weather.isLoading)
                }
            } footer: {
                Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com")!)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .task(id: query) { await search() }
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            searchMessage = nil
            return
        }
        try? await Task.sleep(nanoseconds: 350_000_000)
        guard !Task.isCancelled else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await WeatherService.searchLocations(text)
            guard !Task.isCancelled else { return }
            results = found
            searchMessage = found.isEmpty ? "No places found for “\(text)”." : nil
        } catch {
            guard !Task.isCancelled else { return }
            searchMessage = "Search failed. Check your internet connection."
        }
    }

    private func select(_ location: WeatherLocation) {
        model.settings.weatherLocation = location
        query = ""
        results = []
        searchMessage = nil
    }
}

// MARK: - Shelf

struct ShelfPane: View {
    @EnvironmentObject private var shelf: ShelfModel
    @EnvironmentObject private var model: SettingsModel
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                PaneHeader(pane: .shelf, subtitle: "Drag files onto the notch to keep them handy, then drag them out wherever you need them.")
            }

            Section {
                if shelf.items.isEmpty {
                    Text("The shelf is empty.").foregroundStyle(.secondary)
                } else {
                    ForEach(shelf.items.prefix(12)) { item in
                        HStack(spacing: 10) {
                            Image(nsImage: shelf.icon(for: item))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.displayName).lineLimit(1)
                                Text(item.url.deletingLastPathComponent().path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button("Show") { shelf.reveal(item) }
                                .buttonStyle(.borderless)
                            Button {
                                withAnimation { shelf.remove(item) }
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help("Remove from Shelf")
                        }
                    }
                    if shelf.items.count > 12 {
                        Text("And \(shelf.items.count - 12) more…").foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(shelf.items.count == 1 ? "1 File" : "\(shelf.items.count) Files")
            } footer: {
                Text("The shelf keeps a link to each file, not a copy, so moving or deleting the original takes it off the shelf.")
            }

            Section {
                Toggle("Show File Shelf in the island", isOn: shelfEnabled)
                Button("Clear Shelf", role: .destructive) { confirmClear = true }
                    .disabled(shelf.items.isEmpty)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear the shelf?", isPresented: $confirmClear) {
            Button("Clear Shelf", role: .destructive) { withAnimation { shelf.clear() } }
        } message: {
            Text("Your files stay where they are. They're just removed from the shelf.")
        }
    }

    private var shelfEnabled: Binding<Bool> {
        Binding(
            get: { model.settings.isEnabled(.fileShelf) },
            set: { enabled in
                if let index = model.settings.widgets.firstIndex(where: { $0.kind == .fileShelf }) {
                    model.settings.widgets[index].isEnabled = enabled
                }
            }
        )
    }
}

// MARK: - About

struct AboutPane: View {
    @EnvironmentObject private var model: SettingsModel
    @State private var confirmReset = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("MacNotch")
                        .font(.system(size: 22, weight: .bold))
                    Text(version)
                        .foregroundStyle(.secondary)
                    Text("A Dynamic Island for your MacBook's notch.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            Section("Credits") {
                Link("Weather data by Open-Meteo.com (CC BY 4.0)", destination: URL(string: "https://open-meteo.com")!)
                Text("Album artwork from Apple Music.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
                Button("Quit MacNotch") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset all settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { model.resetToDefaults() }
        } message: {
            Text("Widgets, web pages, weather location and appearance go back to their defaults.")
        }
    }
}
