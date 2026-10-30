import AppKit
import NotchCore

/// Current conditions from Open-Meteo (free, no API key). Refreshes every 15 minutes and after wake.
@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let live: Bool
    private var location: WeatherLocation
    private var unit: TemperatureUnit
    private let cache = CodableDefaults<WeatherSnapshot>(key: StorageKeys.weatherCache)
    private var timer: Timer?
    private var fetchTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    static let refreshInterval: TimeInterval = 15 * 60

    init(live: Bool = true, location: WeatherLocation, unit: TemperatureUnit) {
        self.live = live
        self.location = location
        self.unit = unit
        guard live else { return }

        if let cached = cache.load(), cached.locationName == location.name, cached.unit == unit {
            snapshot = cached
        }

        timer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 60

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.refreshIfStale()
            }
        }

        refresh()
    }

    func configure(location: WeatherLocation, unit: TemperatureUnit) {
        guard location != self.location || unit != self.unit else { return }
        self.location = location
        self.unit = unit
        refresh()
    }

    func refreshIfStale(maxAge: TimeInterval = 10 * 60) {
        guard let snapshot, Date().timeIntervalSince(snapshot.fetchedAt) < maxAge,
              snapshot.locationName == location.name, snapshot.unit == unit
        else {
            refresh()
            return
        }
    }

    func refresh() {
        guard live else { return }
        fetchTask?.cancel()
        let location = self.location
        let unit = self.unit
        isLoading = true
        fetchTask = Task {
            defer { isLoading = false }
            do {
                var request = URLRequest(url: OpenMeteo.forecastURL(for: location, unit: unit))
                request.timeoutInterval = 15
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                let result = try OpenMeteo.decodeForecast(data, unit: unit, locationName: location.name)
                guard !Task.isCancelled else { return }
                snapshot = result
                errorMessage = nil
                cache.save(result)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                errorMessage = (error as? URLError)?.code == .notConnectedToInternet
                    ? "You're offline"
                    : "Weather unavailable"
            }
        }
    }

    func openWeatherApp() {
        let workspace = NSWorkspace.shared
        if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.weather") {
            workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func preview(_ snapshot: WeatherSnapshot?) {
        self.snapshot = snapshot
    }

    /// City search for the settings window.
    nonisolated static func searchLocations(_ query: String) async throws -> [WeatherLocation] {
        guard let url = OpenMeteo.geocodingURL(for: query) else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        return try OpenMeteo.decodeLocations(data)
    }
}
