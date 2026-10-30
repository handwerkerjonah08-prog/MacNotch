import Foundation

public struct ShelfItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    public var addedAt: Date

    public init(id: UUID = UUID(), path: String, addedAt: Date) {
        self.id = id
        self.path = path
        self.addedAt = addedAt
    }

    public var url: URL { URL(fileURLWithPath: path) }
    public var displayName: String { url.lastPathComponent }
}

/// The file shelf keeps references to files (not copies), newest first.
public struct ShelfStore: Codable, Equatable, Sendable {
    public private(set) var items: [ShelfItem]
    public static let maxItems = 40

    public init(items: [ShelfItem] = []) {
        self.items = items
    }

    /// Adds file URLs, skipping duplicates. Returns how many were added.
    @discardableResult
    public mutating func add(_ urls: [URL], now: Date = Date()) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let path = url.standardizedFileURL.path
            guard !path.isEmpty, !items.contains(where: { $0.path == path }) else { continue }
            items.insert(ShelfItem(path: path, addedAt: now), at: 0)
            added += 1
        }
        if items.count > Self.maxItems {
            items.removeLast(items.count - Self.maxItems)
        }
        return added
    }

    public mutating func remove(id: UUID) {
        items.removeAll { $0.id == id }
    }

    public mutating func removeAll() {
        items.removeAll()
    }

    /// Drops entries whose files were moved or deleted.
    public mutating func pruneMissing(fileExists: (String) -> Bool) {
        items.removeAll { !fileExists($0.path) }
    }
}
