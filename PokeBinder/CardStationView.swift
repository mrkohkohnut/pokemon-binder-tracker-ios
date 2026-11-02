import SwiftUI

enum CatalogueFilter: String, CaseIterable, Identifiable {
    case all = "All", forms = "Forms", mega = "Mega", art = "Art rares", promo = "Promos", pictured = "With image"
    var id: String { rawValue }
}

struct CardStationView: View {
    let pokemon: Pokemon
    let owned: OwnedCard?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var cards: [CardOption] = []
    @State private var coverage = ""
    @State private var loading = true
    @State private var loadError: String?
    @State private var language = CardLanguage.english
    @State private var draftId: String?
    @State private var search = ""
    @State private var filter = CatalogueFilter.all
    @State private var limit = 36

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
                // Wide screens: the chosen card stays beside the catalogue.
                if sizeClass == .regular {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 16) { identity(alternates: alternates); languagePicker; preview }
                            .frame(width: 340)
                        catalogueSection(visible, alternates: alternates, megas: megas)
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        identity(alternates: alternates)
                        languagePicker
                        preview
                        catalogueSection(visible, alternates: alternates, megas: megas)
                    }
                    .padding()
                }
            }
            .background(PokeBallBackdrop())
            .navigationTitle(pokemon.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokeRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .task { await load() }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button(role: .destructive) { context.removeCard(for: pokemon.id); dismiss() } label: {
                Text("Mark missing").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(owned == nil)

            Button { context.saveCard(draft, language: language, for: pokemon.id); dismiss() } label: {
                HStack(spacing: 8) {
                    PokeBall(size: 18, top: .white)
                    Text(owned == nil ? "Catch it!" : "Replace card").bold()
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Language printed on your card").font(.caption.bold()).foregroundStyle(.secondary)
            Picker("Language printed on your card", selection: $language) {
                ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
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

    /// Pokédex screen: sprite on a battle platform.
    private func identity(alternates: Int) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Ellipse().fill(Color.pokeGreen.opacity(0.35)).frame(width: 86, height: 22).offset(y: 30)
                Sprite(url: pokemon.spriteURL, silhouette: owned == nil).frame(width: 92, height: 92)
            }
            .frame(width: 104, height: 104)
            .background(LinearGradient(colors: [Color(red: 0.86, green: 0.95, blue: 0.86), .white], startPoint: .top, endPoint: .bottom),
                        in: .rect(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.pokeNavy.opacity(0.8), lineWidth: 3))

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(pokemon.dex).font(.caption.bold().monospacedDigit()).opacity(0.85)
                    Text(owned == nil ? "Missing" : "In binder").font(.caption2.bold())
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(owned == nil ? Color.black.opacity(0.25) : Color.pokeYellow, in: .capsule)
                        .foregroundStyle(owned == nil ? Color.white : Color.pokeNavy)
                }
                Text(pokemon.name).font(.title2.bold())
                Text(owned.map { "\($0.card?.name ?? "Chosen card") · \($0.language.rawValue)" }
                     ?? "Pick the exact printing that belongs in this pocket.")
                    .font(.footnote).opacity(0.9)
                if alternates > 0 {
                    Text("\(alternates) alternate version\(alternates == 1 ? "" : "s") grouped here").font(.caption2.bold()).foregroundStyle(Color.pokeYellow)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(LinearGradient(colors: [.pokeRed, .pokeRedDark], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 20))
    }

    /// The chosen card, with a holo sheen.
    private var preview: some View {
        let card = draft
        return VStack(spacing: 12) {
            Group {
                if let url = card.imageLargeUrl ?? card.imageUrl {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                } else {
                    VStack(spacing: 6) {
                        PokeBall(size: 28)
                        Text("YOUR CARD").font(.caption.weight(.heavy)).foregroundStyle(Color.pokeNavy)
                        Sprite(url: pokemon.spriteURL).frame(height: 110)
                        Text(pokemon.name).font(.caption.bold()).foregroundStyle(Color.pokeNavy)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [.pokeYellow, Color(red: 1, green: 0.93, blue: 0.6)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 10).inset(by: 6).stroke(Color.pokeNavy.opacity(0.3), lineWidth: 2))
                }
            }
            .aspectRatio(5 / 7, contentMode: .fit)
            .frame(maxHeight: 300)
            .overlay {
                LinearGradient(colors: [.clear, .white.opacity(0.35), .clear, Color.megaViolet.opacity(0.15), .clear],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            }
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 8)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    if card.isAlternateForm { Tag(text: card.formLabel ?? "Alternate Form", color: card.form == .mega ? .megaViolet : .pokeBlue) }
                    Tag(text: card.rarity, color: .orange)
                }
                Text(card.name).font(.headline).multilineTextAlignment(.center)
                Text(card.setName).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 0) {
                    stat("Set", card.setCode)
                    stat("No.", card.number)
                    stat("Lang", language.rawValue)
                    if let released = card.releaseDate { stat("Released", released) }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.white, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func catalogueSection(_ visible: [CardOption], alternates: Int, megas: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 0) {
                    Text("AVAILABLE PRINTINGS").font(.caption2.bold()).tracking(1).foregroundStyle(.secondary)
                    Text(loading ? "Searching the Pokédex…" : "\(visible.count) card\(visible.count == 1 ? "" : "s")").font(.title3.bold())
                }
                Spacer()
                if alternates > 0 { Tag(text: "\(alternates) Forms", color: .pokeBlue) }
                if megas > 0 { Tag(text: "\(megas) Mega", color: .megaViolet) }
            }

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search set, number or rarity", text: $search)
            }
            .padding(10)
            .background(.white, in: .capsule)
            .overlay(Capsule().stroke(Color.pokeNavy.opacity(0.12)))
            .onChange(of: search) { limit = 36 }

            filterChips(alternates: alternates, megas: megas)

            Button { draftId = baseCard.id } label: {
                HStack(spacing: 12) {
                    PokeBall(size: 30)
                    VStack(alignment: .leading) {
                        Text("Can’t find your card?").bold()
                        Text("Use an unlisted or base printing").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: draft.id == baseCard.id ? "checkmark.circle.fill" : "chevron.right")
                        .foregroundStyle(draft.id == baseCard.id ? Color.pokeGreen : .secondary)
                }
                .padding(12)
                .background(.white, in: .rect(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(draft.id == baseCard.id ? Color.pokeGreen : .clear, lineWidth: 2))
            }
            .buttonStyle(.plain)

            catalogue(visible)

            if !coverage.isEmpty {
                Text("\(coverage) Catalogue images are artwork references; save the language printed on your physical card separately.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func filterChips(alternates: Int, megas: Int) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CatalogueFilter.allCases.filter { ($0 != .forms || alternates > 0) && ($0 != .mega || megas > 0) }) { option in
                    let active = filter == option
                    Button { filter = option; limit = 36 } label: {
                        Text(option.rawValue).font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(active ? Color.pokeRed : Color.white, in: .capsule)
                            .foregroundStyle(active ? Color.white : Color.pokeNavy)
                            .overlay(Capsule().stroke(Color.pokeNavy.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private func catalogue(_ visible: [CardOption]) -> some View {
        if loading {
            VStack(spacing: 10) {
                // Poké Ball wobble while "catching" the catalogue.
                PokeBall(size: 40)
                    .phaseAnimator([-18.0, 18.0]) { ball, angle in ball.rotationEffect(.degrees(angle), anchor: .bottom) }
                        animation: { _ in .easeInOut(duration: 0.35) }
                Text("Loading every known printing…").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(30)
        } else if let loadError {
            Text("\(loadError) You can still save an unlisted card above.").font(.footnote).foregroundStyle(.red)
        } else if visible.isEmpty {
            Text("No matching cards. Try “All” or clear the catalogue search.").font(.footnote).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                ForEach(visible.prefix(limit)) { card in
                    Button { draftId = card.id } label: { CardChoice(card: card, sprite: pokemon.spriteURL, chosen: draft.id == card.id) }
                        .buttonStyle(.plain)
                }
            }
            if limit < visible.count {
                Button("Show \(min(36, visible.count - limit)) more cards") { limit += 36 }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

private struct CardChoice: View {
    let card: CardOption, sprite: URL, chosen: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Group {
                if let url = card.imageUrl {
                    AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: { Color.black.opacity(0.06) }
                } else {
                    Sprite(url: sprite).padding().frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black.opacity(0.06))
                }
            }
            .aspectRatio(5 / 7, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 8))
            .overlay(alignment: .topTrailing) {
                if chosen { PokeBall(size: 22).padding(5).shadow(radius: 3) }
            }
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? Color.pokeYellow : .clear, lineWidth: 3) }
            .scaleEffect(chosen ? 1.03 : 1)
            .animation(.snappy, value: chosen)

            Text(card.name).font(.caption2.bold()).lineLimit(1)
            Text("\(card.setCode) · \(card.number)").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            if card.isAlternateForm {
                Text(card.formLabel ?? "Alternate Form").font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(card.form == .mega ? Color.megaViolet : Color.pokeBlue)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
