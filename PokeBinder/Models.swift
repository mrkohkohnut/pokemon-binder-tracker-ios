import Foundation
import SwiftData

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

///// One binder pocket, synced to the private CloudKit database by SwiftData.
/// CloudKit needs every attribute optional or defaulted and doesn't allow unique constraints.
@Model
final class BinderEntry {
    var pokemonId: Int = 0
    var cardId: String = ""
    var language: String = CardLanguage.english.rawValue
    var acquiredAt: Date = Date.now
    var updatedAt: Date = Date.now
    var cardJSON: Data?

    init(pokemonId: Int) { self.pokemonId = pokemonId }

    var owned: OwnedCard {
        OwnedCard(cardId: cardId, language: CardLanguage(rawValue: language) ?? .english, acquiredAt: acquiredAt,
                  card: cardJSON.flatMap { try? JSONDecoder().decode(CardOption.self, from: $0) })
    }

    /// Latest entry per Pokémon (two offline devices can each insert one).
    static func collection(_ entries: [BinderEntry]) -> [Int: OwnedCard] {
        Dictionary(entries.map { ($0.pokemonId, $0) }) { $0.updatedAt >= $1.updatedAt ? $0 : $1 }.mapValues(\.owned)
    }
}

extension ModelContext {
    func saveCard(_ card: CardOption, language: CardLanguage, for pokemonId: Int) {
        let existing = entries(for: pokemonId)
        let entry = existing.first ?? BinderEntry(pokemonId: pokemonId)
        if existing.isEmpty { insert(entry) }
        existing.dropFirst().forEach { delete($0) }

        var chosen = card
        chosen.language = language.rawValue
        entry.cardId = card.id
        entry.language = language.rawValue
        entry.cardJSON = try? JSONEncoder().encode(chosen)
        entry.updatedAt = .now
    }

    func removeCard(for pokemonId: Int) {
        entries(for: pokemonId).forEach { delete($0) }
    }

    private func entries(for pokemonId: Int) -> [BinderEntry] {
        (try? fetch(FetchDescriptor<BinderEntry>(predicate: #Predicate { $0.pokemonId == pokemonId },
                                                 sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))) ?? []
    }
}
