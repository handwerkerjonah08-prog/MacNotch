import AppKit
import NotchCore
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// The file shelf: files dropped on the notch, kept as references and persisted across launches.
@MainActor
final class ShelfModel: ObservableObject {
    @Published private(set) var store: ShelfStore
    @Published private(set) var thumbnails: [UUID: NSImage] = [:]

    private let persistence: CodableDefaults<ShelfStore>?

    init(live: Bool = true) {
        persistence = live ? CodableDefaults(key: StorageKeys.shelf) : nil
        store = persistence?.load() ?? ShelfStore()
        if live {
            store.pruneMissing { FileManager.default.fileExists(atPath: $0) }
            store.items.forEach(makeThumbnail)
        }
    }

    var items: [ShelfItem] { store.items }

    @discardableResult
    func add(_ urls: [URL]) -> Int {
        let added = store.add(urls)
        if added > 0 {
            store.items.prefix(added).forEach(makeThumbnail)
            save()
        }
        return added
    }

    func remove(_ item: ShelfItem) {
        store.remove(id: item.id)
        thumbnails[item.id] = nil
        save()
    }

    func clear() {
        store.removeAll()
        thumbnails.removeAll()
        save()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func icon(for item: ShelfItem) -> NSImage {
        thumbnails[item.id] ?? NSWorkspace.shared.icon(forFile: item.path)
    }

    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        NSItemProvider(contentsOf: item.url) ?? NSItemProvider(object: item.url as NSURL)
    }

    /// Re-checks that files still exist, e.g. after one was dragged out and moved.
    func pruneMissing() {
        let before = store.items.count
        store.pruneMissing { FileManager.default.fileExists(atPath: $0) }
        if store.items.count != before {
            save()
        }
    }

    private func save() {
        persistence?.save(store)
    }

    private func makeThumbnail(for item: ShelfItem) {
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 88, height: 88),
            scale: 2,
            representationTypes: .thumbnail
        )
        let id = item.id
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let image = representation?.nsImage else { return }
            Task { @MainActor in
                self?.thumbnails[id] = image
            }
        }
    }

    /// Loads file URLs out of drag providers.
    nonisolated static func fileURLs(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    continuation.resume(returning: url)
                }
            }
            if let url, url.isFileURL {
                urls.append(url)
            }
        }
        return urls
    }
}
