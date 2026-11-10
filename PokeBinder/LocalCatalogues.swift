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

    static func japanese(_ pokemon: Pokemon) async throws -> CardService.Catalogue {
        let name = pokemon.name(in: .japanese)
        async let rarities = rarityCodes(japaneseRarities) { code in
            try await japaneseCards(name, extra: [.init(name: "sc_rare_\(code)", value: "1")]).map(\.cardID)
        }
        let found = try await japaneseCards(name)
        let codes = await rarities
        let cards = found.map { card -> CardOption in
            // /assets/images/card_images/large/<set>/<file>.jpg
            let parts = card.cardThumbFile.split(separator: "/")
            let set = parts.count >= 2 ? String(parts[parts.count - 2]) : "JP"
            let image = URL(string: "https://www.pokemon-card.com\(card.cardThumbFile)")
            let (form, label) = classify(card.cardNameViewText, name, language: .japanese)
            return CardOption(id: "jp:\(card.cardID)", sourceId: "jp-\(card.cardID)", name: card.cardNameViewText,
                              setName: "Japanese · \(set)", setCode: set, number: card.cardID,
                              rarity: codes[card.cardID] ?? "Japanese printing",
                              imageUrl: image, imageLargeUrl: image, language: CardLanguage.japanese.rawValue,
                              form: form, formLabel: label)
        }
        return .init(cards: unique(cards), coverage: "Japanese catalogue from the official Pokémon Card Game site: \(cards.count) printings.")
    }

    static func japaneseArtRareIDs(_ pokemon: Pokemon) async throws -> Set<String> {
        try await Set(japaneseCards(pokemon.name(in: .japanese), extra: [.init(name: "sc_rare_ar", value: "1")]).map { "jp:\($0.cardID)" })
    }

    /// The site's hidden rarity filters (sc_rare_<code>=1), highest first: a card in two lists keeps the first.
    private static let japaneseRarities: [(query: String, label: String)] = [
        ("ar", "AR"), ("sar", "SAR"), ("chr", "CHR"), ("csr", "CSR"), ("ur", "UR"), ("hr", "HR"), ("sr", "SR"),
        ("ssr", "SSR"), ("mur", "MUR"), ("bwr", "BWR"), ("rrr", "RRR"), ("rr", "RR"), ("ma", "MA"), ("rac", "ACE"), ("tr", "TR"),
    ]

    private struct JapanesePage: Decodable {
        struct Card: Decodable { let cardID: String; let cardThumbFile: String; let cardNameViewText: String }
        let maxPage: Int
        let cardList: [Card]?
    }

    /// Every card named after this Pokémon, optionally narrowed by a search filter.
    private static func japaneseCards(_ name: String, extra: [URLQueryItem] = []) async throws -> [JapanesePage.Card] {
        @Sendable func page(_ number: Int) async throws -> JapanesePage {
            var url = URLComponents(string: "https://www.pokemon-card.com/card-search/resultAPI.php")!
            // sm_and_keyword limits the search to card names.
            url.queryItems = [.init(name: "keyword", value: name), .init(name: "sm_and_keyword", value: "true"),
                              .init(name: "regulation_sidebar_form", value: "all"), .init(name: "page", value: String(number))] + extra
            return try await fetchJSON(url.url!)
        }
        let first = try await page(1)
        let rest = try await pages(upTo: first.maxPage, page)
        return ([first] + rest).flatMap { $0.cardList ?? [] }.filter { names($0.cardNameViewText, include: name, of: JAPANESE_NAMES) }
    }

    // MARK: Chinese (asia.pokemon-card.com/tw, HTML list)

    static func chinese(_ pokemon: Pokemon) async throws -> CardService.Catalogue {
        let name = pokemon.name(in: .chinese)
        let keywords = chineseKeywords(pokemon)
        async let rarities = rarityCodes(chineseRarities) { code in
            try await chineseIDs(keywords, extra: [.init(name: "rarity[]", value: code)])
        }
        let ids = try await chineseIDs(keywords).sorted { Int($0) ?? 0 > Int($1) ?? 0 } // Newest first, like the other catalogues.
        let codes = await rarities
        let cards = ids.map { id in
            let image = URL(string: "https://asia.pokemon-card.com/tw/card-img/tw\(String(repeating: "0", count: max(0, 8 - id.count)))\(id).png")
            return CardOption(id: "tw:\(id)", sourceId: "tw-\(id)", name: name, setName: "Traditional Chinese printing",
                              setCode: "TW", number: id, rarity: codes[id] ?? "Chinese printing", imageUrl: image, imageLargeUrl: image,
                              language: CardLanguage.chinese.rawValue, form: .standard, formLabel: "Base Species")
        }
        return .init(cards: cards,
                     coverage: "Chinese catalogue from the official Traditional Chinese card search (Taiwan and Hong Kong): \(cards.count) printings.")
    }

    static func chineseArtRareIDs(_ pokemon: Pokemon) async throws -> Set<String> {
        try await Set(chineseIDs(chineseKeywords(pokemon), extra: [.init(name: "rarity[]", value: "14")]).map { "tw:\($0)" })
    }

    /// The name on the cards, plus any spelling the official site uses that differs from the Pokédex name.
    private static func chineseKeywords(_ pokemon: Pokemon) -> [String] {
        [pokemon.name(in: .chinese)] + (CHINESE_CARD_NAMES[pokemon.id] ?? [])
    }

    /// rarity[] values of the site's filter, highest first.
    private static let chineseRarities: [(query: String, label: String)] = [
        ("14", "AR"), ("15", "SAR"), ("10", "UR"), ("9", "HR"), ("8", "SR"), ("17", "SSR"), ("20", "MUR"), ("19", "BWR"),
        ("22", "FUR"), ("5", "RRR"), ("4", "RR"), ("21", "MA"), ("18", "ACE"), ("16", "S"), ("13", "A"), ("12", "K"), ("7", "TR"),
        ("6", "Promo"),
    ]

    /// Card ids matching any of the keywords. The list pages carry only ids and image links, no names or sets.
    private static func chineseIDs(_ keywords: [String], extra: [URLQueryItem] = []) async throws -> [String] {
        var all: [String] = []
        for keyword in keywords {
            @Sendable func page(_ number: Int) async throws -> String {
                var url = URLComponents(string: "https://asia.pokemon-card.com/tw/card-search/list/")!
                url.queryItems = [.init(name: "keyword", value: keyword), .init(name: "pageNo", value: String(number))] + extra
                let (data, response) = try await URLSession.shared.data(from: url.url!)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                return String(decoding: data, as: UTF8.self)
            }
            let first = try await page(1)
            let total = first.firstMatch(of: /共\s*(\d+)\s*頁/).flatMap { Int($0.1) } ?? 1
            let rest = try await pages(upTo: total, page)
            all += ([first] + rest).flatMap { html in html.matches(of: /card-search\/detail\/(\d+)\//).map { String($0.1) } }
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0).inserted }
    }

    /// Runs one filtered search per rarity at once and maps each card id to its rarity label.
    /// A failed rarity search just leaves those cards unlabelled.
    private static func rarityCodes(_ rarities: [(query: String, label: String)],
                                    _ search: @escaping @Sendable (String) async throws -> [String]) async -> [String: String] {
        let found = await withTaskGroup(of: (Int, [String]).self) { group in
            for (i, rarity) in rarities.enumerated() {
                let query = rarity.query
                group.addTask { (i, (try? await search(query)) ?? []) }
            }
            var found: [Int: [String]] = [:]
            for await (i, ids) in group { found[i] = ids }
            return found
        }
        var labels: [String: String] = [:]
        for (i, rarity) in rarities.enumerated() {
            for id in found[i] ?? [] where labels[id] == nil { labels[id] = rarity.label }
        }
        return labels
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
