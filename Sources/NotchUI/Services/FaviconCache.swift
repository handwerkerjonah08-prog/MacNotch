import AppKit
import NotchCore

/// A site's logo with any solid tile behind it removed, plus whether it's a dark one-color logo
/// that should be inverted to show on dark glass.
struct SiteIcon {
    let image: NSImage
    let invertsOnDark: Bool

    init(image: NSImage) {
        let logo = ImageColor.removingBackground(image) ?? image
        self.image = logo
        invertsOnDark = ImageColor.isDarkMonochromeGlyph(logo)
    }
}

/// Fetches and caches site icons for web page widgets.
@MainActor
final class FaviconCache: ObservableObject {
    @Published private(set) var icons: [String: SiteIcon] = [:]

    private let live: Bool
    private var inFlight: Set<String> = []
    private let directory: URL?

    init(live: Bool = true) {
        self.live = live
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        directory = caches?.appendingPathComponent("MacNotch/SiteIcons-v2", isDirectory: true)
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    func icon(for shortcut: WebShortcut) -> SiteIcon? {
        icons[shortcut.host]
    }

    func load(_ shortcuts: [WebShortcut]) {
        for shortcut in shortcuts {
            load(shortcut)
        }
    }

    func load(_ shortcut: WebShortcut) {
        let host = shortcut.host
        guard !host.isEmpty, icons[host] == nil, !inFlight.contains(host) else { return }

        if let file = fileURL(for: host), let data = try? Data(contentsOf: file), let image = NSImage(data: data) {
            icons[host] = SiteIcon(image: image)
            return
        }
        guard live else { return }

        inFlight.insert(host)
        let candidates = URLNormalizer.faviconCandidates(for: shortcut.url)
        Task {
            if let (data, image) = await Self.bestIcon(from: candidates) {
                icons[host] = SiteIcon(image: image)
                if let file = fileURL(for: host) {
                    try? data.write(to: file, options: .atomic)
                }
            }
            inFlight.remove(host)
        }
    }

    private func fileURL(for host: String) -> URL? {
        let safe = host.replacingOccurrences(of: "/", with: "_")
        return directory?.appendingPathComponent(safe + ".img")
    }

    /// Tries each source and keeps the best icon, preferring sharp ones with transparent backgrounds.
    nonisolated private static func bestIcon(from candidates: [URL]) async -> (Data, NSImage)? {
        var best: (data: Data, image: NSImage, score: Int)?
        for url in candidates {
            guard let (data, image, pixels) = await fetch(url), pixels >= 32 else { continue }
            let transparent = ImageColor.hasTransparentBackground(image)
            if transparent && pixels >= 96 {
                return (data, image)
            }
            let score = pixels * (transparent ? 3 : 1)
            if score > (best?.score ?? 0) {
                best = (data, image, score)
            }
        }
        guard let best else { return nil }
        return (best.data, best.image)
    }

    nonisolated private static func fetch(_ url: URL) async -> (Data, NSImage, Int)? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              !data.isEmpty,
              let image = NSImage(data: data)
        else { return nil }
        let pixels = image.representations.map(\.pixelsWide).max() ?? Int(image.size.width)
        return (data, image, pixels)
    }
}
