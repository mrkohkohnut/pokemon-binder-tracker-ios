import SwiftUI

/// How special a printing is, read from the rarity each catalogue reports
/// (TCGdex names like "Illustration rare", or the printed codes AR, SAR, SR… on Japanese and Chinese cards).
enum RarityTier: Int, Comparable {
    case base, double, ultra, specialArt, art

    static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

    init(_ rarity: String) {
        switch rarity.lowercased() {
        case "illustration rare", "ar", "chr", "character rare", "art rare":
            self = .art
        case "special illustration rare", "sar", "csr", "character super rare":
            self = .specialArt
        case "ultra rare", "hyper rare", "secret rare", "mega hyper rare", "shiny ultra rare", "rare rainbow", "rare secret",
             "sr", "ur", "hr", "ssr", "mur", "bwr", "black white rare", "fur", "futuristic rare":
            self = .ultra
        case "double rare", "rr", "rrr", "holo rare v", "holo rare vmax", "holo rare vstar", "ace spec rare", "ace",
             "radiant rare", "amazing rare", "shiny rare", "shiny rare v", "shiny rare vmax", "s", "a", "k", "tr", "ma",
             "mega attack rare", "full art trainer", "legend", "rare prime", "rare holo lv.x":
            self = .double
        default:
            self = .base
        }
    }

    /// Short code printed in the corner of the pocket.
    static func code(_ rarity: String) -> String? {
        switch rarity.lowercased() {
        case "illustration rare": "AR"
        case "special illustration rare": "SAR"
        case "ultra rare": "UR"
        case "hyper rare", "mega hyper rare": "HR"
        case "secret rare", "rare secret", "rare rainbow": "SR"
        case "shiny ultra rare": "SSR"
        case "double rare": "RR"
        case "black white rare": "BWR"
        case let r where r.count <= 4 && r.allSatisfy(\.isLetter): r.uppercased() // Printed codes: AR, SAR, CHR…
        default: nil
        }
    }

    /// Border for the card or pocket. AR, the collecting goal, gets the rainbow holo.
    var border: AnyShapeStyle {
        switch self {
        case .art:
            AnyShapeStyle(AngularGradient(colors: [.pink, .orange, .yellow, .green, .cyan, .blue, .purple, .pink], center: .center))
        case .specialArt:
            AnyShapeStyle(LinearGradient(colors: [Color(red: 0.95, green: 0.35, blue: 0.75), .megaViolet, Color(red: 0.2, green: 0.2, blue: 0.6)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
        case .ultra:
            AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.88, blue: 0.45), Color(red: 0.8, green: 0.58, blue: 0.1), Color(red: 1, green: 0.9, blue: 0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
        case .double:
            AnyShapeStyle(LinearGradient(colors: [Color(white: 0.92), Color(white: 0.6), Color(white: 0.9)], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .base:
            AnyShapeStyle(Color(.separator))
        }
    }

    var lineWidth: CGFloat { self == .base ? 1 : self >= .specialArt ? 3.5 : 2.5 }
}

extension CardOption {
    var tier: RarityTier { RarityTier(rarity) }
    var rarityCode: String? { RarityTier.code(rarity) }
}

/// Corner chip with the printed rarity code, coloured like its border.
struct RarityChip: View {
    let card: CardOption
    var body: some View {
        if let code = card.rarityCode, card.tier > .base {
            Text(code)
                .font(.system(size: 9, weight: .black, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(card.tier.border, in: .capsule)
                .foregroundStyle(card.tier == .double || card.tier == .ultra ? Color.pokeInk : .white)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        }
    }
}

/// Which caught Pokémon have an AR (Illustration Rare) printed in the card's language,
/// so pockets can say "upgrade to an AR" or "maxed: no AR exists".
@Observable @MainActor
final class ARIndex {
    enum Progress: Equatable { case idle, scanning(done: Int, total: Int) }

    private(set) var progress = Progress.idle
    private var known: [String: Bool]
    private var checkedAt: [String: Date]
    private let defaults = UserDefaults.standard
    /// New sets come out every few months; re-check each Pokémon weekly.
    private let freshFor: TimeInterval = 7 * 24 * 3600

    init() {
        let saved = UserDefaults.standard
        known = (saved.dictionary(forKey: "arKnown") as? [String: Bool]) ?? [:]
        checkedAt = (saved.dictionary(forKey: "arCheckedAt") as? [String: Date]) ?? [:]
    }

    private static func key(_ id: Int, _ language: CardLanguage) -> String { "\(language.rawValue)-\(id)" }

    func hasAR(_ id: Int, _ language: CardLanguage) -> Bool? { known[Self.key(id, language)] }

    /// A loaded catalogue that shows an AR settles it. (No AR in a catalogue isn't proof:
    /// a rarity search may have failed, so "maxed" only ever comes from the dedicated check.)
    func noteAR(in cards: [CardOption], for id: Int, language: CardLanguage) {
        if cards.contains(where: { $0.tier == .art }) { set(true, for: id, language: language) }
    }

    /// Checks every caught Pokémon whose answer is unknown or stale (or all of them when forced).
    /// A saved card that turns out to be an AR gets its rarity filled in (cards saved before rarity was tracked).
    func scan(_ store: CollectionStore, force: Bool = false) async {
        guard progress == .idle else { return }
        let owned = store.owned
        let todo = owned.map { ($0.key, $0.value.language) }.filter { id, language in
            let key = Self.key(id, language)
            return force || known[key] == nil || Date.now.timeIntervalSince(checkedAt[key] ?? .distantPast) > freshFor
        }
        guard !todo.isEmpty else { return }
        progress = .scanning(done: 0, total: todo.count)
        await withTaskGroup(of: (Int, CardLanguage, Set<String>?).self) { group in
            var next = todo.makeIterator()
            func add() {
                guard let item = next.next() else { return }
                let (id, language) = item
                let pokemon = Pokemon.all[id - 1]
                group.addTask {
                    let ids = try? await CardService.artRareIDs(pokemon, language: language)
                    return (id, language, ids)
                }
            }
            for _ in 0..<6 { add() } // Be gentle with the card sites.
            var done = 0
            for await (id, language, answer) in group {
                if let answer {
                    set(!answer.isEmpty, for: id, language: language)
                    if let card = store.owned[id], card.language == language, answer.contains(card.cardId), card.card?.tier != .art {
                        store.markRarity("AR", for: id)
                    }
                }
                done += 1
                progress = .scanning(done: done, total: todo.count)
                add()
            }
        }
        progress = .idle
    }

    private func set(_ value: Bool, for id: Int, language: CardLanguage) {
        let key = Self.key(id, language)
        known[key] = value
        checkedAt[key] = .now
        defaults.set(known, forKey: "arKnown")
        defaults.set(checkedAt, forKey: "arCheckedAt")
    }
}

/// Where a caught Pokémon stands against the "every AR" goal.
enum ARGoal {
    case gotAR, maxed, upgrade, unknown

    init(owned: OwnedCard, index: ARIndex, pokemonId: Int) {
        if owned.card?.tier == .art { self = .gotAR; return }
        switch index.hasAR(pokemonId, owned.language) {
        case false?: self = .maxed
        case true?: self = .upgrade
        case nil: self = .unknown
        }
    }
}
