import AppKit
import Combine
import NotchCore
import SwiftUI

private let musicBundleID = "com.apple.Music"

/// Tracks and controls Apple Music.
/// State comes from Music's `playerInfo` broadcast (no permission needed); artwork, position and
/// playback controls go through AppleScript, which macOS asks permission for once.
@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var state: PlaybackState = .stopped
    @Published private(set) var track: TrackInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: Color = .white
    @Published private(set) var position: PlaybackPosition = .zero
    @Published private(set) var isMusicRunning = false
    @Published private(set) var needsPermission = false

    private let live: Bool
    private let scripts = AppleScriptRunner()
    private var playerInfoObserver: DistributedObserver?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var artworkKey: String?
    private var artworkTask: Task<Void, Never>?

    init(live: Bool = true) {
        self.live = live
        guard live else { return }

        playerInfoObserver = DistributedObserver(name: "com.apple.Music.playerInfo") { [weak self] userInfo in
            let parsed = MusicPlayerInfoParser.parse(userInfo)
            Task { @MainActor in
                self?.apply(state: parsed.state, track: parsed.track, elapsed: nil)
                if parsed.state != .stopped {
                    self?.refreshState()
                }
            }
        }

        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard Self.isMusic(note) else { return }
            Task { @MainActor in self?.isMusicRunning = true }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard Self.isMusic(note) else { return }
            Task { @MainActor in self?.musicDidQuit() }
        })

        isMusicRunning = Self.musicIsRunning()
        if isMusicRunning {
            refreshState()
        }
    }

    // MARK: Derived

    var isPlaying: Bool { state == .playing }
    var hasTrack: Bool { track != nil && state != .stopped }

    func elapsed(at date: Date) -> TimeInterval {
        position.elapsed(at: date, duration: track?.duration ?? 0)
    }

    // MARK: Controls

    func togglePlayPause() {
        guard isMusicRunning else {
            openMusic()
            return
        }
        let now = Date()
        let newState: PlaybackState = state == .playing ? .paused : .playing
        position = PlaybackPosition(elapsed: elapsed(at: now), timestamp: now, isPlaying: newState == .playing)
        state = newState
        runControl("playpause")
    }

    func nextTrack() {
        guard isMusicRunning else { return }
        runControl("next track")
    }

    func previousTrack() {
        guard isMusicRunning else { return }
        runControl("previous track")
    }

    func seek(toFraction fraction: Double) {
        guard isMusicRunning, let duration = track?.duration, duration > 0 else { return }
        let target = min(max(fraction, 0), 1) * duration
        position = PlaybackPosition(elapsed: target, timestamp: Date(), isPlaying: state == .playing)
        runControl("set player position to \(String(format: "%.2f", target))")
    }

    func openMusic() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: musicBundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Re-reads the full player state, including the exact position.
    func refreshState() {
        guard live, Self.musicIsRunning() else { return }
        Task {
            let result = await scripts.run(Self.stateScript)
            switch result {
            case .success(let output):
                needsPermission = false
                handleStateOutput(output)
            case .failure(.notPermitted):
                needsPermission = true
            case .failure:
                break
            }
        }
    }

    // MARK: Preview

    func preview(track: TrackInfo?, state: PlaybackState, artwork: NSImage?, elapsed: TimeInterval) {
        self.track = track
        self.state = state
        self.isMusicRunning = track != nil
        self.position = PlaybackPosition(elapsed: elapsed, timestamp: Date(), isPlaying: false)
        setArtwork(artwork)
    }

    // MARK: Internals

    private func runControl(_ command: String) {
        Task {
            let script = "if application \"Music\" is running then tell application \"Music\" to \(command)"
            let result = await scripts.run(script)
            if case .failure(.notPermitted) = result {
                needsPermission = true
            } else {
                needsPermission = false
            }
            refreshState()
        }
    }

    private func handleStateOutput(_ output: AppleScriptRunner.Output) {
        let values = output.strings
        let playback = PlaybackState(musicValue: values.first ?? "stopped")
        guard playback != .stopped else {
            apply(state: .stopped, track: nil, elapsed: nil)
            return
        }
        guard values.count >= 6 else {
            // Playing something without track details (e.g. a radio stream): keep what we have.
            apply(state: playback, track: nil, elapsed: nil)
            return
        }
        let info = TrackInfo(
            title: values[1].isEmpty ? "Unknown Title" : values[1],
            artist: values[2],
            album: values[3],
            duration: max(0, output.numbers[4])
        )
        apply(state: playback, track: info, elapsed: max(0, output.numbers[5]))
    }

    private func apply(state newState: PlaybackState, track newTrack: TrackInfo?, elapsed: TimeInterval?) {
        let now = Date()
        let trackChanged = newTrack?.key != track?.key

        if newState == .stopped {
            state = .stopped
            track = nil
            position = .zero
            setArtwork(nil)
            artworkKey = nil
            return
        }

        isMusicRunning = true
        let currentElapsed = trackChanged ? 0 : self.elapsed(at: now)
        position = PlaybackPosition(
            elapsed: elapsed ?? currentElapsed,
            timestamp: now,
            isPlaying: newState == .playing
        )
        if let newTrack {
            track = newTrack
        }
        state = newState

        if let key = track?.key, key != artworkKey {
            artworkKey = key
            loadArtwork(for: track)
        }
    }

    private func musicDidQuit() {
        isMusicRunning = false
        apply(state: .stopped, track: nil, elapsed: nil)
    }

    private func loadArtwork(for track: TrackInfo?) {
        artworkTask?.cancel()
        guard let track else { return }
        let key = track.key
        artworkTask = Task {
            var image: NSImage?
            if case .success(let output) = await scripts.run(Self.artworkScript), let data = output.data {
                image = NSImage(data: data)
            }
            if image == nil {
                image = await Self.fetchStoreArtwork(for: track)
            }
            guard !Task.isCancelled, key == self.track?.key else { return }
            setArtwork(image)
        }
    }

    private func setArtwork(_ image: NSImage?) {
        withAnimation(.easeInOut(duration: 0.3)) {
            artwork = image
            if let image, let average = ImageColor.averageColor(of: image) {
                accent = Color(rgb: ColorMath.vibrantAccent(from: average))
            } else {
                accent = Color.white.opacity(0.92)
            }
        }
    }

    // MARK: Helpers

    nonisolated private static func isMusic(_ note: Notification) -> Bool {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        return app?.bundleIdentifier == musicBundleID
    }

    nonisolated static func musicIsRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: musicBundleID).isEmpty
    }

    /// Falls back to the iTunes Search API when a streamed track has no embedded artwork.
    nonisolated private static func fetchStoreArtwork(for track: TrackInfo) async -> NSImage? {
        let term = [track.artist, track.album.isEmpty ? track.title : track.album]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !term.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: track.album.isEmpty ? "song" : "album"),
            URLQueryItem(name: "limit", value: "1")
        ]
        guard let url = components.url else { return nil }

        struct SearchResponse: Decodable {
            struct Item: Decodable { let artworkUrl100: String? }
            let results: [Item]
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let small = response.results.first?.artworkUrl100,
                  let large = URL(string: small.replacingOccurrences(of: "100x100bb", with: "600x600bb"))
            else { return nil }
            let (imageData, _) = try await URLSession.shared.data(from: large)
            return NSImage(data: imageData)
        } catch {
            return nil
        }
    }

    // Every script checks `is running` first so MacNotch never relaunches Music after you quit it.
    private static let stateScript = """
    if application "Music" is running then
        tell application "Music"
            set ps to player state as string
            if ps is "stopped" then return {ps}
            try
                set t to current track
                set d to duration of t
                if d is missing value then set d to 0
                set p to player position
                if p is missing value then set p to 0
                return {ps, name of t, artist of t, album of t, d, p}
            on error
                return {ps}
            end try
        end tell
    end if
    return {"stopped"}
    """

    private static let artworkScript = """
    if application "Music" is running then
        tell application "Music"
            try
                set a to artwork 1 of current track
                try
                    return raw data of a
                on error
                    return data of a
                end try
            end try
        end tell
    end if
    return ""
    """
}

/// Receives distributed notifications even while MacNotch is in the background.
/// (The block-based API is paused whenever the app is inactive, which for MacNotch is always.)
final class DistributedObserver: NSObject {
    private let handler: ([AnyHashable: Any]) -> Void

    init(name: String, handler: @escaping ([AnyHashable: Any]) -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(received(_:)),
            name: Notification.Name(name),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func received(_ note: Notification) {
        handler(note.userInfo ?? [:])
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }
}

enum ImageColor {
    /// Saturation-weighted average so vivid parts of the artwork win over gray backgrounds.
    static func averageColor(of image: NSImage) -> RGB? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 10
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side, height: side,
                bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var red = 0.0, green = 0.0, blue = 0.0, total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.1 else { continue }
            let r = Double(pixels[index]) / 255 / alpha
            let g = Double(pixels[index + 1]) / 255 / alpha
            let b = Double(pixels[index + 2]) / 255 / alpha
            let saturation = ColorMath.hsb(from: RGB(red: r, green: g, blue: b)).saturation
            let weight = 0.15 + saturation * saturation * 2
            red += r * weight
            green += g * weight
            blue += b * weight
            total += weight
        }
        guard total > 0 else { return nil }
        return RGB(red: red / total, green: green / total, blue: blue / total)
    }
}
