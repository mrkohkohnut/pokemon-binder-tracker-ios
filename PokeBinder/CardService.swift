import Foundation

/// Card catalogues per printed language, each from the sources that actually have that language's cards:
/// - English: TCGdex.
/// - Japanese: the official pokemon-card.com search, plus TCGdex for older sets it doesn't carry (1996 onwards).
/// - Chinese: the official Traditional Chinese (Taiwan/Hong Kong) search at asia.pokemon-card.com,
///   plus TCGdex's Simplified Chinese (mainland) cards.
/// - Korean: the matching Japanese sets, with Japanese pictures.
enum CardService {
    struct Catalogue: Codable {
        var cards: [CardOption]
        var coverage: String
        var fetchedAt = Date.now
        /// Cards that weren't there at the previous weekly check.
        var newSinceLastCheck: Set<String> = []
    }

    /// The saved catalogue while it's under a week old; otherwise fetched from the card sources and saved.
    /// Falls back to the saved copy, however old, when the sources can't be reached.
    static func catalogue(for pokemon: Pokemon, language: CardLanguage, refresh: Bool = false) async throws -> Catalogue {
        let saved = CatalogueCache.load(pokemon.id, language)
        if let saved, !refresh, Date.now.timeIntervalSince(saved.fetchedAt) < CatalogueCache.maxAge { return saved }
        do {
            var fresh = try await download(pokemon, language: language)
            if let saved {
                let before = Set(saved.cards.map(\.id))
                fresh.newSinceLastCheck = Set(fresh.cards.map(\.id)).subtracting(before)
            }
            CatalogueCache.save(fresh, pokemon.id, language)
            return fresh
        } catch {
            if let saved { return saved }
            throw error
        }
    }


    private static func download(_ pokemon: Pokemon, language: CardLanguage) async throws -> Catalogue {
        switch language {
        case .english: return try await english(pokemon)
        case .japanese: return try await LocalCatalogues.japanese(pokemon)
        case .chinese: return try await LocalCatalogues.chinese(pokemon)
        case .korean:
            // No Korean card database with pictures (TCGdex has a few hundred Korean cards, without images);
            // Korean sets mirror the Japanese ones, so show those pictures.
            var catalogue = try await LocalCatalogues.japanese(pokemon)
            catalogue.cards = catalogue.cards.map { card in
                var card = card
                card.name = card.name.replacingOccurrences(of: pokemon.name(in: .japanese), with: pokemon.name(in: .korean)) // Keeps ex, V…
                card.setName = "Korean · \(card.setCode) (Japanese picture)"
                card.language = CardLanguage.korean.rawValue
                return card
            }
            catalogue.coverage = "Korean catalogue: \(catalogue.cards.count) printings, shown with the matching Japanese card pictures."
            return catalogue
        }
    }

    /// Ids (as in `CardOption.id`) of this Pokémon's ARs (Illustration Rares) in that language. Empty: no AR exists.
    static func artRareIDs(_ pokemon: Pokemon, language: CardLanguage) async throws -> Set<String> {
        switch language {
        case .english:
            struct Hit: Decodable { let id: String; let name: String; let category: String? }
            struct Response: Decodable { struct Body: Decodable { let d: [Hit]; let n: [Hit] }; let data: Body }
            var request = URLRequest(url: URL(string: "https://api.tcgdex.net/v2/graphql")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "query": """
                query($d: Int!, $n: String!) {
                  d: cards(filters: { dexId: $d, rarity: "Illustration rare" }) { id name category }
                  n: cards(filters: { name: $n, rarity: "Illustration rare" }) { id name category }
                }
                """,
                "variables": ["d": pokemon.id, "n": pokemon.name] as [String: Any],
            ] as [String: Any])
            let body: Response = try await fetch(request)
            let named = body.data.n.filter { $0.category == "Pokemon" && nameIncludes($0.name, pokemon.name) }
            return Set((body.data.d + named).map { "tcgdex:\($0.id)" })
        case .japanese, .korean: return try await LocalCatalogues.japaneseArtRareIDs(pokemon)
        case .chinese: return try await LocalCatalogues.chineseArtRareIDs(pokemon)
        }
    }

    /// TCG Pocket (the phone game) cards live in TCGdex too, but can't go in a binder.
    private static func isPocketSet(_ setCode: String) -> Bool {
        setCode.wholeMatch(of: /[AB]\d+[a-z]?|P-[A-Z]/) != nil
    }

    private struct GraphCard: Decodable {
        struct CardSet: Decodable { let id: String; let name: String; let releaseDate: String? }
        let id: String, localId: String, name: String
        let category: String?, image: String?, rarity: String?, illustrator: String?
        let set: CardSet
    }

    private struct CardBrief: Decodable { let id: String, localId: String, name: String; let image: String? }

    private struct GraphResponse: Decodable {
        struct DataBody: Decodable { let dexCards: [GraphCard]?; let namedCards: [GraphCard]? }
        let data: DataBody?
    }

    private static let query = """
    query CardsByPokemon($dexId: Int!, $name: String!) {
      dexCards: cards(filters: { dexId: $dexId }) { id localId name category image rarity illustrator set { id name releaseDate } }
      namedCards: cards(filters: { name: $name }) { id localId name category image rarity illustrator set { id name releaseDate } }
    }
    """

    private static func english(_ pokemon: Pokemon) async throws -> Catalogue {
        var cards: [CardOption]
        var expanded = true
        do {
            cards = try await expandedCatalogue(pokemon)
        } catch {
            cards = try await fallbackCatalogue(pokemon)
            expanded = false
        }

        let mega = cards.filter { $0.form == .mega }.count
        let alternates = cards.filter(\.isAlternateForm).count
        let forms = alternates == 0 ? "" :
            " \(alternates) alternate-form artwork\(alternates == 1 ? " is" : "s are") grouped under \(pokemon.name)" +
            (mega > 0 ? ", including \(mega) Mega Evolution card\(mega == 1 ? "" : "s")" : "") + "."
        let coverage = expanded
            ? "English catalogue from TCGdex: \(cards.count) printings, including regular cards, illustration rares, promos and special releases.\(forms)"
            : "English catalogue (fallback): \(cards.count) printings.\(forms) Some set and rarity details are temporarily unavailable."
        return Catalogue(cards: cards, coverage: coverage)
    }

    private static func expandedCatalogue(_ pokemon: Pokemon) async throws -> [CardOption] {
        var request = URLRequest(url: URL(string: "https://api.tcgdex.net/v2/graphql")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "query": query, "variables": ["dexId": pokemon.id, "name": pokemon.name] as [String: Any],
        ] as [String: Any])
        let payload: GraphResponse = try await fetch(request)
        guard let dexCards = payload.data?.dexCards else { throw URLError(.badServerResponse) }

        let dex = dexCards.filter { $0.category == nil || $0.category == "Pokemon" }
        let named = (payload.data?.namedCards ?? []).filter { $0.category == "Pokemon" && nameIncludes($0.name, pokemon.name) }
        return sorted(merge(dex.map { fromGraph($0, pokemon.name) }, named.map { fromGraph($0, pokemon.name) }))
            .filter { !isPocketSet($0.setCode) }
    }

    private static func fallbackCatalogue(_ pokemon: Pokemon) async throws -> [CardOption] {
        async let named = namedBriefs(pokemon)
        let dex: [CardBrief] = try await fetch(URLRequest(url: URL(string: "https://api.tcgdex.net/v2/en/cards?dexId=eq:\(pokemon.id)")!))
        let namedCards = await named.filter { nameIncludes($0.name, pokemon.name) }
        return sorted(merge(dex.map { fromBrief($0, pokemon.name) }, namedCards.map { fromBrief($0, pokemon.name) }))
            .filter { !isPocketSet($0.setCode) }
    }

    private static func namedBriefs(_ pokemon: Pokemon) async -> [CardBrief] {
        var url = URLComponents(string: "https://api.tcgdex.net/v2/en/cards")!
        url.queryItems = [.init(name: "name", value: pokemon.name), .init(name: "category", value: "Pokemon")]
        let briefs: [CardBrief]? = try? await fetch(URLRequest(url: url.url!))
        return briefs ?? []
    }

    static func fetch<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: - Mapping

    private static func image(_ base: String?, _ quality: String) -> URL? {
        base.flatMap { URL(string: "\($0)/\(quality).webp") }
    }

    private static func fromGraph(_ card: GraphCard, _ pokemonName: String) -> CardOption {
        let (form, label) = classify(card.name, pokemonName)
        return CardOption(
            id: "tcgdex:\(card.id)", sourceId: card.id, name: card.name,
            setName: card.set.name, setCode: card.set.id, number: card.localId,
            rarity: card.rarity?.isEmpty == false ? card.rarity! : "Unlisted rarity",
            imageUrl: image(card.image, "low"), imageLargeUrl: image(card.image, "high"),
            illustrator: card.illustrator, releaseDate: card.set.releaseDate,
            language: CardLanguage.english.rawValue, form: form, formLabel: label
        )
    }

    private static func fromBrief(_ card: CardBrief, _ pokemonName: String) -> CardOption {
        let (form, label) = classify(card.name, pokemonName)
        let setCode = card.id.range(of: "-", options: .backwards).map { String(card.id[..<$0.lowerBound]) } ?? card.id
        return CardOption(
            id: "tcgdex:\(card.id)", sourceId: card.id, name: card.name,
            setName: setCode, setCode: setCode, number: card.localId, rarity: "Catalogue card",
            imageUrl: image(card.image, "low"), imageLargeUrl: image(card.image, "high"),
            illustrator: nil, releaseDate: nil, language: CardLanguage.english.rawValue, form: form, formLabel: label
        )
    }

    private static func merge(_ catalogues: [CardOption]...) -> [CardOption] {
        var seen: [String: Int] = [:], result: [CardOption] = []
        for card in catalogues.joined() {
            if let index = seen[card.sourceId] { result[index] = card } else { seen[card.sourceId] = result.count; result.append(card) }
        }
        return result
    }

    private static func sorted(_ cards: [CardOption]) -> [CardOption] {
        cards.sorted { a, b in
            let (da, db) = (a.releaseDate ?? "", b.releaseDate ?? "")
            if da != db { return da > db }
            if (a.imageUrl != nil) != (b.imageUrl != nil) { return a.imageUrl != nil }
            if a.setName != b.setName { return a.setName < b.setName }
            return a.number.localizedStandardCompare(b.number) == .orderedAscending
        }
    }

    // MARK: - Name matching

    static func normalise(_ value: String) -> String {
        value.replacingOccurrences(of: "♀", with: " female ")
            .replacingOccurrences(of: "♂", with: " male ")
            .folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
    }

    static func nameIncludes(_ cardName: String, _ pokemonName: String) -> Bool {
        let card = normalise(cardName), pokemon = normalise(pokemonName)
        return card == pokemon || card.hasPrefix("\(pokemon) ") || card.hasSuffix(" \(pokemon)") || card.contains(" \(pokemon) ")
    }

    static func classify(_ cardName: String, _ pokemonName: String) -> (CardForm, String) {
        let card = normalise(cardName), pokemon = normalise(pokemonName)
        func named(_ prefix: String) -> Bool { card == "\(prefix) \(pokemon)" || card.hasPrefix("\(prefix) \(pokemon) ") }

        if named("mega") || named("m") { return (.mega, "Mega Evolution") }
        if let region = ["alolan", "galarian", "hisuian", "paldean"].first(where: named) {
            return (.regional, "\(region.capitalized) Form")
        }
        if cardName.contains("&") { return (.paired, "Paired Pokémon") }
        if card == pokemon || card.hasPrefix("\(pokemon) ") { return (.standard, "Base Species") }
        return (.special, "Special Version")
    }
}
