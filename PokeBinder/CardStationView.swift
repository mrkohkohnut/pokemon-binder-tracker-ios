import SwiftUI

enum CatalogueFilter: String, CaseIterable, Identifiable {
    case all = "All", forms = "Forms", mega = "Mega", art = "Art rares", promo = "Promos", pictured = "With image"
    var id: String { rawValue }
}

struct CardStationView: View {
    let pokemon: Pokemon
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var cards: [CardOption] = []
    @State private var coverage = ""
    @State private var loading = true
    @State private var loadError: String?
    @State private var language = CardLanguage.english
    @State private var draftId: String?
    @State private var search = ""
    @State private var filter = CatalogueFilter.all
    @State private var limit = 36

    private var owned: OwnedCard? { store.owned[pokemon.id] }

    private var baseCard: CardOption {
        CardOption(id: "base:\(pokemon.id)", sourceId: "base-\(pokemon.id)", name: "\(pokemon.name) · unlisted card",
                   setName: "Any printing in your binder", setCode: "OWN", number: pokemon.dex, rarity: "Manual entry",
                   language: language.rawValue, form: .standard, formLabel: "Base Species")
    }

    /// Catalogue plus a previously saved card that's no longer listed.
    private var selectable: [CardOption] {
        if let legacy = owned?.card, !cards.contains(where: { $0.id == owned?.cardId }), !legacy.id.hasPrefix("base:") {
            return [legacy] + cards
        }
        return cards
    }

    private var draft: CardOption {
        ([baseCard] + selectable).first { $0.id == draftId } ?? selectable.first ?? baseCard
    }

    private var visibleCards: [CardOption] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let matching = selectable.filter { card in
            let rarity = card.rarity.lowercased()
            let matchesSearch = q.isEmpty || [card.name, card.setName, card.setCode, card.number, card.rarity]
                .contains { $0.lowercased().contains(q) }
            let matchesFilter = switch filter {
            case .all: true
            case .forms: card.isAlternateForm
            case .mega: card.form == .mega
            case .art: ["illustration", "character", "secret", "hyper", "ultra rare", "shiny", "amazing", "crown"].contains { rarity.contains($0) }
            case .promo: rarity.contains("promo") || card.setName.lowercased().contains("promo")
            case .pictured: card.imageUrl != nil
            }
            return matchesSearch && matchesFilter
        }
        guard filter == .all else { return matching }
        let order: [CardForm?] = [.mega, .regional, .paired, .special, .standard, nil]
        return order.flatMap { form in matching.filter { $0.form == form } }
    }

    var body: some View {
        let visible = visibleCards
        let alternates = selectable.filter(\.isAlternateForm).count
        let megas = selectable.filter { $0.form == .mega }.count

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identity(alternates: alternates)

                    Picker("Language printed on your card", selection: $language) {
                        ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    preview

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(loading ? "Searching the Pokédex…" : "\(visible.count) card\(visible.count == 1 ? "" : "s")")
                                .font(.headline)
                            Spacer()
                            if alternates > 0 { Tag(text: "\(alternates) Forms", color: .blue) }
                            if megas > 0 { Tag(text: "\(megas) Mega", color: .megaViolet) }
                        }
                        TextField("Search set, number or rarity", text: $search)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: search) { limit = 36 }
                        filterChips(alternates: alternates, megas: megas)

                        Button { draftId = baseCard.id } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Can’t find your card?").bold()
                                    Text("Use an unlisted or base printing").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: draft.id == baseCard.id ? "checkmark.circle.fill" : "circle") }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)

                        catalogue(visible)
                    }

                    if !coverage.isEmpty {
                        Text("\(coverage) Catalogue images are artwork references; save the language printed on your physical card separately.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(pokemon.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button("Mark missing", role: .destructive) { store.remove(pokemon.id); dismiss() }
                        .disabled(owned == nil)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(owned == nil ? "Add to binder" : "Replace card") {
                        store.save(draft, language: language, for: pokemon.id)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        language = owned?.language ?? .english
        draftId = owned?.cardId
        do {
            let catalogue = try await CardService.catalogue(for: pokemon)
            cards = catalogue.cards
            coverage = catalogue.coverage
        } catch {
            loadError = "The live catalogue is temporarily unavailable."
        }
        loading = false
    }

    private func identity(alternates: Int) -> some View {
        HStack(spacing: 14) {
            Sprite(url: pokemon.spriteURL)
                .frame(width: 84, height: 84)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(pokemon.dex).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Tag(text: owned == nil ? "Missing" : "In binder", color: owned == nil ? .gray : .pokeGreen)
                }
                Text(pokemon.name).font(.title2.bold())
                Text(owned.map { "\($0.card?.name ?? "Chosen card") · \($0.language.rawValue)" }
                     ?? "Pick the exact printing that belongs in this pocket.")
                    .font(.footnote).foregroundStyle(.secondary)
                if alternates > 0 {
                    Text("\(alternates) alternate version\(alternates == 1 ? "" : "s") grouped here").font(.caption2).foregroundStyle(.blue)
                }
            }
        }
    }

    private var preview: some View {
        let card = draft
        return HStack(alignment: .top, spacing: 14) {
            Group {
                if let url = card.imageLargeUrl ?? card.imageUrl {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                } else {
                    VStack {
                        Text("YOUR CARD").font(.caption.bold())
                        Sprite(url: pokemon.spriteURL)
                        Text(pokemon.name).font(.caption2)
                    }
                    .padding(8)
                    .background(Color.pokeYellow.opacity(0.3), in: .rect(cornerRadius: 8))
                }
            }
            .frame(width: 130, height: 182)

            VStack(alignment: .leading, spacing: 6) {
                if card.isAlternateForm { Tag(text: card.formLabel ?? "Alternate Form", color: card.form == .mega ? .megaViolet : .blue) }
                Tag(text: card.rarity, color: .orange)
                Text(card.name).font(.headline)
                Text(card.setName).font(.subheadline).foregroundStyle(.secondary)
                Grid(alignment: .leading, verticalSpacing: 2) {
                    GridRow { Text("Set").foregroundStyle(.secondary); Text(card.setCode) }
                    GridRow { Text("Number").foregroundStyle(.secondary); Text(card.number) }
                    GridRow { Text("Language").foregroundStyle(.secondary); Text(language.rawValue) }
                    if let released = card.releaseDate {
                        GridRow { Text("Released").foregroundStyle(.secondary); Text(released) }
                    }
                }
                .font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 16))
    }

    private func filterChips(alternates: Int, megas: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(CatalogueFilter.allCases.filter { ($0 != .forms || alternates > 0) && ($0 != .mega || megas > 0) }) { option in
                    Button(option.rawValue) { filter = option; limit = 36 }
                        .buttonStyle(.bordered)
                        .tint(filter == option ? Color.pokeRed : Color.gray)
                }
            }
        }
    }

    @ViewBuilder
    private func catalogue(_ visible: [CardOption]) -> some View {
        if loading {
            HStack { ProgressView(); Text("Loading every known printing…").font(.footnote) }
                .frame(maxWidth: .infinity).padding()
        } else if let loadError {
            Text("\(loadError) You can still save an unlisted card above.").font(.footnote).foregroundStyle(.red)
        } else if visible.isEmpty {
            Text("No matching cards. Try “All” or clear the catalogue search.").font(.footnote).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
                ForEach(visible.prefix(limit)) { card in
                    Button { draftId = card.id } label: { CardChoice(card: card, sprite: pokemon.spriteURL, chosen: draft.id == card.id) }
                        .buttonStyle(.plain)
                }
            }
            if limit < visible.count {
                Button("Show \(min(36, visible.count - limit)) more cards") { limit += 36 }
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CardChoice: View {
    let card: CardOption, sprite: URL, chosen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ZStack(alignment: .topTrailing) {
                if let url = card.imageUrl {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color(.tertiarySystemFill) }
                } else {
                    Sprite(url: sprite).padding().background(Color(.tertiarySystemFill))
                }
                if chosen {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.white, Color.pokeGreen).padding(4)
                }
            }
            .aspectRatio(5 / 7, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 6))
            Text(card.name).font(.caption2.bold()).lineLimit(1)
            Text("\(card.setCode) · \(card.number)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            if card.isAlternateForm { Text(card.formLabel ?? "Alternate Form").font(.system(size: 9, weight: .semibold)).foregroundStyle(.blue) }
        }
        .padding(4)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Color.pokeGreen : .clear, lineWidth: 2) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

private struct Tag: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15), in: .capsule).foregroundStyle(color)
    }
}
