import CryptoKit
import SwiftUI
import UIKit

/// Everything the app shows is kept on the device: card catalogues (refreshed weekly) and every image
/// (cards, sprites, artwork), which never change once printed, so they're downloaded once and kept.
enum LocalStore {
    static let root: URL = {
        let url = URL.applicationSupportDirectory.appending(path: "PokeBinder", directoryHint: .isDirectory)
        var dir = url
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Re-downloadable, so keep it out of iCloud/iTunes backups.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? dir.setResourceValues(values)
        return url
    }()

    static func folder(_ name: String) -> URL {
        let url = root.appending(path: name, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Bytes used on the device, for the "stored on this phone" line.
    static func size() -> Int {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let file = files?.nextObject() as? URL {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

// MARK: - Images

/// Downloads an image once and serves it from disk (and memory) afterwards.
actor ImageStore {
    static let shared = ImageStore()

    private let folder = LocalStore.folder("Images")
    nonisolated(unsafe) private let memory = NSCache<NSURL, UIImage>() // NSCache is thread-safe.
    private var inFlight: [URL: Task<UIImage?, Never>] = [:]

    init() { memory.countLimit = 400 }

    nonisolated func cached(_ url: URL) -> UIImage? { memory.object(forKey: url as NSURL) }

    func image(for url: URL) async -> UIImage? {
        if let hit = memory.object(forKey: url as NSURL) { return hit }
        if let running = inFlight[url] { return await running.value }
        let file = folder.appending(path: LocalStore.fileName(for: url.absoluteString))
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: data) else { return nil } // Not saved, so a failed download is retried later.
            try? data.write(to: file, options: .atomic)
            return image
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { memory.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// Drop-in for AsyncImage that reads from the on-device image store.
struct CachedImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    init(url: URL?, @ViewBuilder content: @escaping (Image) -> Content, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        // Memory hits draw straight away, so flipping binder pages doesn't flash placeholders.
        if let url, let image = loaded?.url == url ? loaded?.image : ImageStore.shared.cached(url) {
            content(Image(uiImage: image))
        } else {
            placeholder()
                .task(id: url) {
                    guard let url, let image = await ImageStore.shared.image(for: url) else { return }
                    loaded = (url, image)
                }
        }
    }
}

// MARK: - Catalogues

/// Each Pokémon's catalogue per language, saved after every download. Shown from disk; fetched again
/// from the card sources once it's a week old (new sets come out every few months), or on request.
/// When a source is down, the saved copy is used however old it is.
enum CatalogueCache {
    static let maxAge: TimeInterval = 7 * 24 * 3600
    /// Bump when the sources or their parsing change, so old saved catalogues are fetched again.
    private static let version = 2
    private static let folder = LocalStore.folder("Catalogues")

    private static func file(_ id: Int, _ language: CardLanguage) -> URL {
        folder.appending(path: "v\(version)-\(language.rawValue)-\(id).json")
    }

    static func load(_ id: Int, _ language: CardLanguage) -> CardService.Catalogue? {
        guard let data = try? Data(contentsOf: file(id, language)) else { return nil }
        return try? JSONDecoder().decode(CardService.Catalogue.self, from: data)
    }

    static func save(_ catalogue: CardService.Catalogue, _ id: Int, _ language: CardLanguage) {
        guard let data = try? JSONEncoder().encode(catalogue) else { return }
        try? data.write(to: file(id, language), options: .atomic)
    }
}
