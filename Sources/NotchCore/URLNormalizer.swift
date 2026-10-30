import Foundation

public enum URLNormalizer {
    /// Turns user input like "discord.com/app" into a valid https URL, or nil if it isn't a web address.
    public static func normalize(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: { $0.isWhitespace }) else { return nil }

        if !text.contains("://") {
            text = "https://" + text
        }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              isValidHost(host)
        else { return nil }

        var normalized = components
        normalized.scheme = scheme
        normalized.host = host
        return normalized.url
    }

    static func isValidHost(_ host: String) -> Bool {
        if host == "localhost" { return true }
        guard host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))
        return host.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static let knownNames: [String: String] = [
        "youtube.com": "YouTube",
        "github.com": "GitHub",
        "chatgpt.com": "ChatGPT",
        "mail.google.com": "Gmail",
        "calendar.google.com": "Calendar",
        "docs.google.com": "Google Docs",
        "drive.google.com": "Google Drive",
        "x.com": "X",
        "create.roblox.com": "Roblox Creator Hub",
        "open.spotify.com": "Spotify",
        "linkedin.com": "LinkedIn",
        "tiktok.com": "TikTok"
    ]

    /// A friendly default name for a URL, e.g. "https://www.discord.com" -> "Discord".
    public static func suggestedName(for url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
        if let known = knownNames[host] { return known }

        let labels = host.split(separator: ".")
        // Use the registrable name: "app.discord.com" -> "discord", "bbc.co.uk" -> "bbc".
        let secondLevelSuffixes: Set<String> = ["co", "com", "org", "net", "gov", "ac", "edu"]
        var candidate: Substring = labels.first ?? ""
        if labels.count >= 2 {
            candidate = labels[labels.count - 2]
            if labels.count >= 3, secondLevelSuffixes.contains(String(candidate)) {
                candidate = labels[labels.count - 3]
            }
        }
        guard let first = candidate.first else { return host }
        return first.uppercased() + candidate.dropFirst()
    }

    /// Icon sources, best first. The apple-touch-icon is the high resolution square app icon most sites ship.
    public static func faviconCandidates(for url: URL) -> [URL] {
        guard let host = url.host, let scheme = url.scheme else { return [] }
        var result: [URL] = []
        if let touch = URL(string: "\(scheme)://\(host)/apple-touch-icon.png") {
            result.append(touch)
        }
        var bareHost = host.lowercased()
        if bareHost.hasPrefix("www.") { bareHost = String(bareHost.dropFirst(4)) }
        if let google = URL(string: "https://www.google.com/s2/favicons?domain=\(bareHost)&sz=128") {
            result.append(google)
        }
        if let duck = URL(string: "https://icons.duckduckgo.com/ip3/\(bareHost).ico") {
            result.append(duck)
        }
        return result
    }
}
