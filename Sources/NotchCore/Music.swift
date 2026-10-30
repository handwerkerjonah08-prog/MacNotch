import Foundation

public enum PlaybackState: String, Equatable, Sendable {
    case playing, paused, stopped

    public init(musicValue: String) {
        switch musicValue.lowercased() {
        case "playing": self = .playing
        case "paused": self = .paused
        default: self = .stopped
        }
    }
}

public struct TrackInfo: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var album: String
    /// Seconds. Zero for radio streams with no fixed length.
    public var duration: TimeInterval

    public init(title: String, artist: String, album: String, duration: TimeInterval) {
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
    }

    /// Identity used to decide when to reload artwork.
    public var key: String { "\(title)\u{1F}\(artist)\u{1F}\(album)" }
}

/// Parses the `com.apple.Music.playerInfo` distributed notification, which needs no permission.
public enum MusicPlayerInfoParser {
    public static func parse(_ userInfo: [AnyHashable: Any]) -> (state: PlaybackState, track: TrackInfo?) {
        let state = PlaybackState(musicValue: userInfo["Player State"] as? String ?? "Stopped")
        guard state != .stopped else { return (state, nil) }

        let title = (userInfo["Name"] as? String) ?? ""
        let artist = (userInfo["Artist"] as? String) ?? (userInfo["Stream Title"] as? String) ?? ""
        let album = (userInfo["Album"] as? String) ?? ""
        let milliseconds = number(userInfo["Total Time"]) ?? 0

        guard !title.isEmpty || !artist.isEmpty else { return (state, nil) }
        let track = TrackInfo(
            title: title.isEmpty ? "Unknown Title" : title,
            artist: artist,
            album: album,
            duration: max(0, milliseconds / 1000)
        )
        return (state, track)
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let double as Double: return double
        case let int as Int: return Double(int)
        case let string as String: return Double(string)
        default: return nil
        }
    }
}

/// Elapsed time anchored to a moment, so the UI can tick without polling Music every second.
public struct PlaybackPosition: Equatable, Sendable {
    public var elapsed: TimeInterval
    public var timestamp: Date
    public var isPlaying: Bool

    public init(elapsed: TimeInterval, timestamp: Date, isPlaying: Bool) {
        self.elapsed = elapsed
        self.timestamp = timestamp
        self.isPlaying = isPlaying
    }

    public static let zero = PlaybackPosition(elapsed: 0, timestamp: .distantPast, isPlaying: false)

    public func elapsed(at date: Date, duration: TimeInterval) -> TimeInterval {
        var value = elapsed
        if isPlaying {
            value += max(0, date.timeIntervalSince(timestamp))
        }
        value = max(0, value)
        if duration > 0 {
            value = min(value, duration)
        }
        return value
    }

    public func progress(at date: Date, duration: TimeInterval) -> Double {
        guard duration > 0 else { return 0 }
        return elapsed(at: date, duration: duration) / duration
    }
}

public enum TimeFormatting {
    /// 0:05, 3:41, 1:02:09
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded(.down))) : 0
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%ld:%02ld:%02ld", hours, minutes, secs)
        }
        return String(format: "%ld:%02ld", minutes, secs)
    }

    public static func remaining(elapsed: TimeInterval, duration: TimeInterval) -> String {
        let left = max(0, duration.rounded(.down) - elapsed.rounded(.down))
        return "-" + clock(left)
    }
}
