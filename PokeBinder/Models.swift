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

/// Device-local collection, saved as JSON in Documents.
// ponytail: device-only storage; add iCloud (NSUbiquitousKeyValueStore/CloudKit) if multi-device sync is needed.
@Observable
final class CollectionStore {
    private(set) var owned: [Int: OwnedCard] = [:]
    private let fileURL = URL.documentsDirectory.appending(path: "binder-collection.json")

    init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Int: OwnedCard].self, from: data) {
            owned = saved
        }
    }

    func save(_ card: CardOption, language: CardLanguage, for pokemonId: Int) {
        var chosen = card
        chosen.language = language.rawValue
        owned[pokemonId] = OwnedCard(
            cardId: card.id,
            language: language,
            acquiredAt: owned[pokemonId]?.acquiredAt ?? .now,
            card: chosen
        )
        persist()
    }

    func remove(_ pokemonId: Int) {
        owned[pokemonId] = nil
        persist()
    }

    private func persist() {
        do {
            try JSONEncoder().encode(owned).write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save collection: \(error)")
        }
    }
}
