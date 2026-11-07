import SwiftUI

enum CatalogueFilter: String, CaseIterable, Identifiable {
    case all = "All", forms = "Forms", mega = "Mega", art = "Art rares", promo = "Promos", pictured = "With image"
    var id: String { rawValue }
}

struct CardStationView: View {
    let pokemon: Pokemon
    let owned: OwnedCard?
    @Environment(CollectionStore.self) private var store
    var onCatch: (Pokemon) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    @State private var width: CGFloat = 0

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
                // Wide screens (unfolded, landscape): the chosen card stays beside the catalogue.
                if width >= 640 {
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background {
                ZStack {
                    RegionBackdrop(accent: region.accent)
                    SpriteParade(caught: Array(store.owned.keys), count: 5)
                }
            }
            .navigationTitle(pokemon.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Label("Close", systemImage: "xmark") }
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .task { await load() }
        }
        .tint(region.accent)
    }

    private var region: Generation { Generation.of(pokemon.id) }

    private var actions: some View {
        HStack(spacing: 12) {
            if owned != nil {
                Button(role: .destructive) { store.remove(pokemon.id); dismiss() } label: {
                    Label("Release", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .secondaryButton()
            }

            Button {
                store.save(draft, language: language, for: pokemon.id)
                if owned == nil { onCatch(pokemon) }
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    PokeBall(size: 20, top: .white)
                    Text(owned == nil ? "Catch \(pokemon.name)!" : "Swap card").bold().lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .prominentButton()
        }
        .controlSize(.large)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity)
        .background {
            if #unavailable(iOS 26) { Rectangle().fill(.bar).ignoresSafeArea() }
        }
    }

    private var languagePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Language printed on your card").font(.caption.bold()).foregroundStyle(.secondary)
            Picker("Language printed on your card", selection: $language) {
                ForEach(CardLanguage.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .background(Color(.secondarySystemGroupedBackground), in: .capsule) // Hide roaming Pokémon behind it.
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

    /// Pokédex entry: the Pokémon standing in a spotlight of its home region's colour.
    private func identity(alternates: Int) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(.white.opacity(0.18)).frame(width: 170, height: 170).blur(radius: 18)
                Ellipse().fill(.black.opacity(0.2)).frame(width: 130, height: 20).blur(radius: 5).offset(y: 80)
                Sprite(url: pokemon.artworkURL, silhouette: owned == nil, pixelated: false).frame(width: 170, height: 170)
                    .modifier(IdleBounce(excited: owned != nil))
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
            }
            .frame(height: 190)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text(pokemon.dex).monospacedDigit()
                    Text("·")
                    Text(region.shortName)
                }
                .font(.subheadline.weight(.semibold)).opacity(0.85)

                Text(owned == nil ? "Who’s that Pokémon? It’s \(pokemon.name)!" : pokemon.name)
                    .font(owned == nil ? .title3.bold() : .largeTitle.bold())
                    .multilineTextAlignment(.center)

                HStack(spacing: 6) {
                    Label(owned == nil ? "Not caught" : "Caught", systemImage: owned == nil ? "circle.dashed" : "checkmark.circle.fill")
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(owned == nil ? 0.2 : 0.95), in: .capsule)
                        .foregroundStyle(owned == nil ? Color.white : region.accent)
                    if alternates > 0 {
                        Text("\(alternates) alternate form\(alternates == 1 ? "" : "s")")
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.white.opacity(0.2), in: .capsule)
                    }
                }

                if let owned {
                    Text("\(owned.card?.name ?? "Chosen card") · \(owned.language.rawValue)")
                        .font(.footnote).opacity(0.85).multilineTextAlignment(.center)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity)
        .background {
            region.accent
                .overlay(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.25)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topTrailing) {
                    PokeBall(size: 260, top: .white, bottom: .white.opacity(0.5)).opacity(0.07).offset(x: 90, y: -70)
                }
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
        }
        .accessibilityElement(children: .combine)
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
                    .environment(\.colorScheme, .light)
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
        .card()
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
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color(.tertiarySystemFill), in: .capsule)
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
                .card(16)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(draft.id == baseCard.id ? Color.pokeGreen : .clear, lineWidth: 2))
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
                    Button { withAnimation(.snappy) { filter = option }; limit = 36 } label: {
                        Text(option.rawValue).font(.caption.bold())
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(active ? region.accent : Color(.tertiarySystemFill), in: .capsule)
                            .foregroundStyle(active ? Color.white : Color.primary)
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
                Text("Searching tall grass for every printing…").font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(30)
        } else if let loadError {
            Text("\(loadError) You can still save an unlisted card above.").font(.footnote).foregroundStyle(.red)
        } else if visible.isEmpty {
            Text("No matching cards. Try “All” or clear the catalogue search.").font(.footnote).foregroundStyle(.secondary)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 12)], spacing: 14) {
                ForEach(visible.prefix(limit)) { card in
                    Button { draftId = card.id } label: { CardChoice(card: card, sprite: pokemon.spriteURL, chosen: draft.id == card.id, accent: region.accent) }
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
    let card: CardOption, sprite: URL, chosen: Bool, accent: Color

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
            .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(chosen ? accent : .clear, lineWidth: 3) }
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
