import Foundation
import Observation

enum CardLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "English", japanese = "Japanese", chinese = "Chinese", korean = "Korean"
    var id: String { rawValue }
}

enum CardForm: String, Codable {
    case standard, mega, regional, paired, special
}

struct CardOption: Codable, Hashable, Identifiable {
    var id: String
    var sourceId: String
    var name: String
    var setName: String
    var setCode: String
    var number: String
    var rarity: String
    var imageUrl: URL?
    var imageLargeUrl: URL?
    var illustrator: String?
    var releaseDate: String?
    var language: String
    var form: CardForm?
    var formLabel: String?

    var isAlternateForm: Bool { form != nil && form != .standard }
}

struct OwnedCard: Codable, Hashable {
    var cardId: String
    var language: CardLanguage
    var acquiredAt: Date
    var card: CardOption?
}

struct Pokemon: Identifiable, Hashable {
    let id: Int
    let name: String
    var dex: String { String(format: "#%04d", id) }
    var spriteURL: URL { URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/\(id).png")! }
    var artworkURL: URL { URL(string: "https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/other/official-artwork/\(id).png")! }

    static let all: [Pokemon] = POKEMON_NAMES.enumerated().map { Pokemon(id: $0.offset + 1, name: $0.element) }
}

struct Generation: Identifiable, Hashable {
    let id: String, label: String, range: ClosedRange<Int>

    static let all: [Generation] = [
        .init(id: "all", label: "All regions", range: 1...1025),
        .init(id: "kanto", label: "Kanto · Gen I", range: 1...151),
        .init(id: "johto", label: "Johto · Gen II", range: 152...251),
        .init(id: "hoenn", label: "Hoenn · Gen III", range: 252...386),
        .init(id: "sinnoh", label: "Sinnoh · Gen IV", range: 387...493),
        .init(id: "unova", label: "Unova · Gen V", range: 494...649),
        .init(id: "kalos", label: "Kalos · Gen VI", range: 650...721),
        .init(id: "alola", label: "Alola · Gen VII", range: 722...809),
        .init(id: "galar", label: "Galar · Gen VIII", range: 810...905),
        .init(id: "paldea", label: "Paldea · Gen IX", range: 906...1025),
    ]
}

/// The binder, cached on the device and synced through an `/api/sync` endpoint: the Mac mini server
/// (Server/sync_server.py at pokemon.kohkohnut.ing) by default, or the web app, which speaks the same protocol.
/// Phones share a binder by sharing a sync code, so it works with any signing (FlareStore included).
@Observable @MainActor
final class CollectionStore {
    enum SyncStatus: Equatable { case off, syncing, synced, failed(String) }

    private(set) var owned: [Int: OwnedCard] = [:]
    private(set) var status = SyncStatus.off
    private(set) var syncCode: String? { didSet { defaults.set(syncCode, forKey: "syncCode") } }
    var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL") } }
    static let defaultServer = "https://pokemon.kohkohnut.ing"

    /// Shared code baked into builds made on the Mac mini, so every phone joins the same binder with no setup.
    /// Lives in the gitignored PokeBinder/auto-sync-code.txt (the repo is public); builds without it fall back to manual codes.
    static let automaticCode: String? = {
        guard let url = Bundle.main.url(forResource: "auto-sync-code", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let code = text.uppercased().filter { $0.isLetter || $0.isNumber }
        return code.count >= 20 ? code : nil
    }()

    var isAutomatic: Bool { syncCode != nil && syncCode == Self.automaticCode }

    /// Local edits not yet accepted by the server; a pull never overwrites them.
    private var dirty: Bool { didSet { defaults.set(dirty, forKey: "syncDirty") } }
    private var pushing = false
    private let defaults = UserDefaults.standard
    private let fileURL = URL.documentsDirectory.appending(path: "binder-collection.json")

    init() {
        let saved = UserDefaults.standard
        syncCode = saved.string(forKey: "syncCode")
        serverURL = saved.string(forKey: "serverURL").flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultServer
        dirty = saved.bool(forKey: "syncDirty")
        if let data = try? Data(contentsOf: fileURL), let saved = try? Self.decode(data) { owned = saved }
    }

    // MARK: Editing

    func save(_ card: CardOption, language: CardLanguage, for pokemonId: Int) {
        var chosen = card
        chosen.language = language.rawValue
        owned[pokemonId] = OwnedCard(cardId: card.id, language: language,
                                     acquiredAt: owned[pokemonId]?.acquiredAt ?? .now, card: chosen)
        changed()
    }

    /// Fills in the rarity of a saved card (it was saved before rarity was tracked).
    func markRarity(_ rarity: String, for pokemonId: Int) {
        guard var entry = owned[pokemonId], var card = entry.card, card.rarity != rarity else { return }
        card.rarity = rarity
        entry.card = card
        owned[pokemonId] = entry
        changed()
    }

    func remove(_ pokemonId: Int) {
        owned[pokemonId] = nil
        changed()
    }

    private func changed() {
        dirty = true
        try? Self.encode(owned.mapKeys).write(to: fileURL, options: .atomic)
        Task { await push() }
    }

    // MARK: Linking

    /// Start syncing: this device's binder becomes the shared one.
    func createSyncCode() async {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        syncCode = String((0..<20).map { _ in alphabet.randomElement()! })
        dirty = true
        await push()
    }

    /// Join a binder started on another phone, keeping cards caught here too.
    func link(code: String) async {
        let clean = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count >= 20 else { status = .failed("That sync code is too short."); return }
        syncCode = clean
        status = .syncing
        do {
            owned = try await fetchRemote().merging(owned) { _, local in local }
            dirty = true
            try? Self.encode(owned.mapKeys).write(to: fileURL, options: .atomic)
            await push()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func unlink() {
        // Remember the choice so automatic sync doesn't re-link straight away.
        if isAutomatic { defaults.set(true, forKey: "automaticSyncOff") }
        syncCode = nil
        status = .off
    }

    /// Join the built-in binder on launch, keeping any cards already caught on this phone.
    /// Phones already on a manual code move over once; after that a manual code someone picks is respected.
    func linkAutomaticallyIfNeeded() async {
        guard let code = Self.automaticCode, !isAutomatic, !defaults.bool(forKey: "automaticSyncOff") else { return }
        if syncCode != nil, defaults.bool(forKey: "movedToAutomaticSync") { return }
        defaults.set(true, forKey: "movedToAutomaticSync")
        await link(code: code)
    }

    /// Switch this phone (back) to the built-in binder.
    func useAutomaticSync() async {
        guard let code = Self.automaticCode else { return }
        defaults.set(false, forKey: "automaticSyncOff")
        await link(code: code)
    }

    // MARK: Sync

    /// Fetch the shared binder. Pushes instead if this device has unsent edits.
    func pull() async {
        guard syncCode != nil, !pushing else { return }
        if dirty { await push(); return }
        status = .syncing
        do {
            let remote = try await fetchRemote()
            guard !dirty else { return } // Edited while fetching; that push wins.
            if remote != owned {
                owned = remote
                try? Self.encode(owned.mapKeys).write(to: fileURL, options: .atomic)
            }
            status = .synced
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func push() async {
        guard syncCode != nil, !pushing else { return }
        pushing = true
        defer { pushing = false }
        status = .syncing
        // Loop so edits made while a request is in flight are sent too.
        while dirty {
            let snapshot = owned
            do {
                var request = try request()
                request.httpMethod = "PUT"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try Self.encode(["collection": snapshot.mapKeys])
                _ = try await send(request)
                if owned == snapshot { dirty = false }
            } catch {
                status = .failed(error.localizedDescription)
                return
            }
        }
        status = .synced
    }

    private func fetchRemote() async throws -> [Int: OwnedCard] {
        struct Body: Decodable { let collection: [String: OwnedCard] }
        let data = try await send(try request())
        guard let body = try? Self.decoder.decode(Body.self, from: data) else { throw SyncError.unreadable }
        return Dictionary(uniqueKeysWithValues: body.collection.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    private func request() throws -> URLRequest {
        let base = serverURL.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let code = syncCode, let url = URL(string: "\(base)/api/sync"), url.scheme == "https" else {
            throw SyncError.noServer
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return data
        case 401: throw SyncError.badCode
        default: throw SyncError.server(String(data: data, encoding: .utf8)?.prefix(200).description ?? "")
        }
    }

    enum SyncError: LocalizedError {
        case noServer, badCode, unreadable, server(String)
        var errorDescription: String? {
            switch self {
            case .noServer: "Add your sync server’s https address in Sync settings."
            case .badCode: "The server didn’t accept this sync code."
            case .unreadable: "The server sent something unexpected. Check the sync server address and that the Mac mini is on."
            case .server(let message): "The server couldn’t save the binder. \(message)"
            }
        }
    }

    // MARK: Coding (same JSON shape as the web app: string keys, ISO 8601 dates)

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func decode(_ data: Data) throws -> [Int: OwnedCard] {
        let saved = try decoder.decode([String: OwnedCard].self, from: data)
        return Dictionary(uniqueKeysWithValues: saved.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    /// Accepts dates with or without fractional seconds (the web app writes them with).
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()
}

private extension Dictionary where Key == Int {
    var mapKeys: [String: Value] { Dictionary<String, Value>(uniqueKeysWithValues: map { (String($0.key), $0.value) }) }
}
