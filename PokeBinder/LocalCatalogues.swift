import Foundation

extension Pokemon {
    /// The name printed on cards in that language.
    func name(in language: CardLanguage) -> String {
        switch language {
        case .english: name
        case .japanese: JAPANESE_NAMES[id - 1]
        case .korean: KOREAN_NAMES[id - 1]
        case .chinese: CHINESE_NAMES[id - 1]
        }
    }
}

/// Japanese and Chinese catalogues, read from the official card searches.
enum LocalCatalogues {
    // MARK: Japanese (www.pokemon-card.com, JSON)

    private struct JapanesePage: Decodable {
        struct Card: Decodable { let cardID: String; let cardThumbFile: String; let cardNameViewText: String }
        let maxPage: Int
        let cardList: [Card]?
    }

    static func japanese(_ pokemon: Pokemon) async throws -> CardService.Catalogue {
        let name = pokemon.name(in: .japanese)
        @Sendable func page(_ number: Int) async throws -> JapanesePage {
            var url = URLComponents(string: "https://www.pokemon-card.com/card-search/resultAPI.php")!
            // sm_and_keyword limits the search to card names.
            url.queryItems = [.init(name: "keyword", value: name), .init(name: "sm_and_keyword", value: "true"),
                              .init(name: "regulation_sidebar_form", value: "all"), .init(name: "page", value: String(number))]
            return try await fetchJSON(url.url!)
        }
        let first = try await page(1)
        let rest = try await pages(upTo: first.maxPage, page)
        let cards = ([first] + rest).flatMap { $0.cardList ?? [] }
            .filter { names($0.cardNameViewText, include: name, of: JAPANESE_NAMES) }
            .map { card -> CardOption in
                // /assets/images/card_images/large/<set>/<file>.jpg
                let parts = card.cardThumbFile.split(separator: "/")
                let set = parts.count >= 2 ? String(parts[parts.count - 2]) : "JP"
                let image = URL(string: "https://www.pokemon-card.com\(card.cardThumbFile)")
                let (form, label) = classify(card.cardNameViewText, name, language: .japanese)
                return CardOption(id: "jp:\(card.cardID)", sourceId: "jp-\(card.cardID)", name: card.cardNameViewText,
                                  setName: "Japanese · \(set)", setCode: set, number: card.cardID, rarity: "Japanese printing",
                                  imageUrl: image, imageLargeUrl: image, language: CardLanguage.japanese.rawValue,
                                  form: form, formLabel: label)
            }
        return .init(cards: unique(cards), coverage: "Japanese catalogue from the official Pokémon Card Game site: \(cards.count) printings.")
    }

    // MARK: Chinese (asia.pokemon-card.com/tw, HTML list)

    static func chinese(_ pokemon: Pokemon) async throws -> CardService.Catalogue {
        let name = pokemon.name(in: .chinese)
        @Sendable func page(_ number: Int) async throws -> String {
            var url = URLComponents(string: "https://asia.pokemon-card.com/tw/card-search/list/")!
            url.queryItems = [.init(name: "keyword", value: name), .init(name: "pageNo", value: String(number))]
            let (data, response) = try await URLSession.shared.data(from: url.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            return String(decoding: data, as: UTF8.self)
        }
        let first = try await page(1)
        // ponytail: regex over the list page; it only carries card ids and image links, no names or sets.
        let total = first.firstMatch(of: /共\s*(\d+)\s*頁/).flatMap { Int($0.1) } ?? 1
        let rest = try await pages(upTo: total, page)
        let ids = ([first] + rest).flatMap { html in html.matches(of: /card-search\/detail\/(\d+)\//).map { String($0.1) } }
            .sorted { Int($0) ?? 0 > Int($1) ?? 0 } // Newest first, like the other catalogues.
        let cards = ids.map { id in
            let image = URL(string: "https://asia.pokemon-card.com/tw/card-img/tw\(String(repeating: "0", count: max(0, 8 - id.count)))\(id).png")
            return CardOption(id: "tw:\(id)", sourceId: "tw-\(id)", name: name, setName: "Traditional Chinese printing",
                              setCode: "TW", number: id, rarity: "Chinese printing", imageUrl: image, imageLargeUrl: image,
                              language: CardLanguage.chinese.rawValue, form: .standard, formLabel: "Base Species")
        }
        return .init(cards: unique(cards),
                     coverage: "Chinese catalogue from the official Traditional Chinese card search (Taiwan and Hong Kong): \(cards.count) printings.")
    }

    // MARK: Helpers

    /// Fetches result pages 2…last at the same time, in order.
    private static func pages<T: Sendable>(upTo last: Int, _ fetch: @escaping @Sendable (Int) async throws -> T) async throws -> [T] {
        let numbers = last < 2 ? [] : Array((2...min(last, 40))) // ponytail: cap at 40 pages per Pokémon
        return try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for n in numbers { group.addTask { (n, try await fetch(n)) } }
            var results: [Int: T] = [:]
            for try await (n, value) in group { results[n] = value }
            return numbers.compactMap { results[$0] }
        }
    }

    private static func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func unique(_ cards: [CardOption]) -> [CardOption] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.id).inserted }
    }

    /// The card is about this Pokémon, not one whose name merely contains it (ミュウ vs ミュウツー).
    static func names(_ cardName: String, include name: String, of all: [String]) -> Bool {
        guard cardName.contains(name) else { return false }
        return !all.contains { other in other.count > name.count && other.contains(name) && cardName.contains(other) }
    }

    static func classify(_ cardName: String, _ name: String, language: CardLanguage) -> (CardForm, String) {
        let mega = ["メガ\(name)", "M\(name)", "Ｍ\(name)", "超級\(name)"]
        let regions = ["アローラ": "Alolan", "ガラル": "Galarian", "ヒスイ": "Hisuian", "パルデア": "Paldean",
                       "阿羅拉": "Alolan", "伽勒爾": "Galarian", "洗翠": "Hisuian", "帕底亞": "Paldean"]
        if mega.contains(where: cardName.hasPrefix) { return (.mega, "Mega Evolution") }
        if let region = regions.first(where: { cardName.hasPrefix($0.key) }) { return (.regional, "\(region.value) Form") }
        if cardName.contains("&") || cardName.contains("＆") { return (.paired, "Paired Pokémon") }
        if cardName.hasPrefix(name) { return (.standard, "Base Species") }
        return (.special, "Special Version")
    }
}
