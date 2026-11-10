import SwiftUI

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All", caught = "Caught", missing = "Missing", needAR = "Need AR"
    var id: String { rawValue }
}

struct BinderView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(ARIndex.self) private var arIndex
    @Environment(\.scenePhase) private var scenePhase
    @State private var showSync = false
    @State private var query = ""
    @State private var status = StatusFilter.all
    @State private var language: CardLanguage?
    @State private var generation = Generation.all[0]
    @State private var page = 0
    @State private var forward = true
    @State private var selected: Pokemon?
    @State private var gotcha: Pokemon?
    @State private var pendingGotcha: Pokemon?
    @State private var width: CGFloat = 0

    /// Matches the physical binder: 4×4 pockets a page. Wide screens show an open two-page spread.
    /// Decided by measured width, not size class: foldables report compact even when wide.
    private var spread: Bool { width >= 700 }
    private let perPage = 16

    private func matching(_ collection: [Int: OwnedCard]) -> [Pokemon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        return Pokemon.all.filter { p in
            let owned = collection[p.id]
            return generation.range.contains(p.id)
                && (q.isEmpty || p.name.lowercased().contains(q) || String(format: "%04d", p.id).contains(q))
                && (status == .all
                    || (status == .needAR ? owned.map { ARGoal(owned: $0, index: arIndex, pokemonId: p.id) == .upgrade } ?? false
                                          : (status == .caught) == (owned != nil)))
                && (language == nil || owned?.language == language)
        }
    }

    var body: some View {
        let collection = store.owned
        let filtered = matching(collection)
        let step = perPage * (spread ? 2 : 1)
        let totalSteps = max(1, (filtered.count + step - 1) / step)
        let current = min(page, totalSteps - 1)
        let shown = Array(filtered.dropFirst(current * step).prefix(step))

        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    TrainerCard(region: generation, caught: collection.keys.filter(generation.range.contains).count)
                        .padding(.horizontal)

                    ARGoalBar(owned: collection.filter { generation.range.contains($0.key) })
                        .padding(.horizontal)

                    RegionBadges(collection: collection, selection: $generation)

                    Picker("Binder status", selection: $status) {
                        ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .background(Color(.secondarySystemGroupedBackground), in: .capsule) // Hide roaming Pokémon behind it.
                    .padding(.horizontal)

                    if shown.isEmpty {
                        ContentUnavailableView {
                            Label { Text("No Pokémon found") } icon: { PokeBall(size: 52) }
                        } description: { Text("Try a different name, region, or binder filter.") }
                    } else {
                        // Pokémon hanging out on top of the binder.
                        PokemonLedge(caught: Array(collection.keys), count: spread ? 8 : 5)
                            .padding(.horizontal, 28)
                            .padding(.bottom, -22)

                        ZStack {
                            BinderSpread(pokemon: shown, perPage: perPage, spread: spread, collection: collection) { selected = $0 }
                                .id("\(generation.id)-\(current)-\(spread)")
                                .transition(.push(from: forward ? .trailing : .leading))
                        }
                        .padding(.horizontal)
                        .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                            if drag.translation.width < -60, current < totalSteps - 1 { turn(to: current + 1, from: current) }
                            if drag.translation.width > 60, current > 0 { turn(to: current - 1, from: current) }
                        })

                        pager(current: current, total: totalSteps, count: filtered.count)
                    }
                }
                .padding(.bottom, 24)
                .frame(maxWidth: spread ? 1200 : 600)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background {
                ZStack {
                    RegionBackdrop(accent: generation.accent)
                    SpriteParade(caught: Array(collection.keys), count: spread ? 12 : 8)
                }
            }
            .navigationTitle("Poké Binder")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSync = true } label: { Label("Sync", systemImage: store.status.symbol) }
                        .accessibilityValue(store.status.label)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Card language", selection: $language) {
                            Text("Any language").tag(CardLanguage?.none)
                            ForEach(CardLanguage.allCases) { Text($0.rawValue).tag(Optional($0)) }
                        }
                    } label: {
                        Label("Card language", systemImage: language == nil ? "globe" : "globe.badge.chevron.backward")
                    }
                }
            }
            .refreshable { await store.pull() }
            // Pick up catches from the other phone while the binder is open.
            // Poll every 15 s while open; use push if server cost or latency becomes a concern.
            .task {
                await store.linkAutomaticallyIfNeeded()
                while !Task.isCancelled {
                    await store.pull()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
            // Check new catches (and cards swapped to another language) for whether an AR exists.
            .task(id: collection.mapValues(\.language)) { await arIndex.scan(store) }
            .onChange(of: scenePhase) { if scenePhase == .active { Task { await store.pull() } } }
            .sheet(isPresented: $showSync) { SyncView() }
            .searchable(text: $query, prompt: "Name or Pokédex number")
            .onChange(of: query) { page = 0 }
            .onChange(of: status) { page = 0 }
            .onChange(of: language) { page = 0 }
            .onChange(of: generation) { page = 0 }
            .onChange(of: spread) { page = 0 }
            .sheet(item: $selected, onDismiss: {
                // Celebrate once the sheet is out of the way.
                withAnimation(.bouncy) { gotcha = pendingGotcha }
                pendingGotcha = nil
            }) { pokemon in
                CardStationView(pokemon: pokemon, owned: collection[pokemon.id], language: language ?? .english) { pendingGotcha = $0 }
            }
        }
        .overlay(alignment: .top) { gotchaBanner }
        .sensoryFeedback(.success, trigger: gotcha)
        .tint(generation.accent)
    }

    private func turn(to target: Int, from current: Int) {
        forward = target > current
        withAnimation(.smooth(duration: 0.35)) { page = target }
    }

    private func pager(current: Int, total: Int, count: Int) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Button { turn(to: current - 1, from: current) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(current == 0)
                .accessibilityLabel("Previous page")

                Text("Page \(current + 1) of \(total)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .contentTransition(.numericText(value: Double(current)))
                    .frame(minWidth: 120)

                Button { turn(to: current + 1, from: current) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(current >= total - 1)
                .accessibilityLabel("Next page")
            }
            .font(.body.weight(.semibold))
            .padding(.horizontal, 6)
            .glassSurface(Capsule(), interactive: true)

            Text("\(count) Pokémon in this view").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gotchaBanner: some View {
        if let gotcha {
            HStack(spacing: 12) {
                Sprite(url: gotcha.spriteURL).frame(width: 44, height: 44)
                PokeBall(size: 26)
                    .phaseAnimator([0.0, -22, 22, -14, 0]) { ball, angle in
                        ball.rotationEffect(.degrees(angle), anchor: .bottom)
                    } animation: { _ in .easeInOut(duration: 0.22) }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Gotcha!").font(.headline)
                    Text("\(gotcha.name) was added to your binder.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .glassSurface(Capsule())
            .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: gotcha) {
                try? await Task.sleep(for: .seconds(2.6))
                withAnimation(.smooth) { self.gotcha = nil }
            }
        }
    }
}

// MARK: - Trainer card

/// Region-coloured Pokédex progress card with a Poké Ball progress dial.
private struct TrainerCard: View {
    let region: Generation
    let caught: Int
    private var total: Int { region.range.count }
    private var fraction: Double { Double(caught) / Double(total) }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text("\(region.shortName.uppercased()) POKÉDEX")
                } icon: {
                    Image(systemName: "circle.circle.fill")
                }
                .font(.caption.weight(.heavy)).tracking(0.8).opacity(0.85)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(caught, format: .number).font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: Double(caught)))
                    Text("/ \(total.formatted())").font(.title3.weight(.semibold)).opacity(0.75)
                }
                .monospacedDigit()

                Text(caught == total ? "Region complete. You’re a Pokémon Master!" : "\((total - caught).formatted()) still to catch")
                    .font(.subheadline.weight(.medium)).opacity(0.9)
            }
            Spacer(minLength: 0)

            ZStack {
                Circle().stroke(.white.opacity(0.22), lineWidth: 10)
                Circle().trim(from: 0, to: fraction)
                    .stroke(.white, style: .init(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.15), radius: 3)
                VStack(spacing: 3) {
                    PokeBall(size: 34, top: region.accent)
                    Text(fraction, format: .percent.precision(.fractionLength(fraction > 0 && fraction < 0.1 ? 1 : 0)))
                        .font(.caption.bold().monospacedDigit())
                }
            }
            .frame(width: 100, height: 100)
            .animation(.smooth, value: fraction)
        }
        .foregroundStyle(.white)
        .padding(20)
        .background {
            region.accent
                .overlay(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.22)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .trailing) {
                    PokeBall(size: 220, top: .white, bottom: .white.opacity(0.5)).opacity(0.08).offset(x: 110, y: 80)
                }
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .shadow(color: region.accent.opacity(0.35), radius: 18, y: 10)
            .animation(.smooth, value: region)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(region.shortName) Pokédex: \(caught) of \(total) Pokémon caught")
    }
}

// MARK: - Region badges

/// Gym-badge style region picker with per-region progress rings.
private struct RegionBadges: View {
    let collection: [Int: OwnedCard]
    @Binding var selection: Generation

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Generation.all) { gen in
                    badge(gen)
                }
            }
            .padding(.vertical, 4)
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    private func badge(_ gen: Generation) -> some View {
        let active = gen == selection
        let caught = collection.keys.filter(gen.range.contains).count
        let fraction = Double(caught) / Double(gen.range.count)

        return Button { withAnimation(.smooth) { selection = gen } } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle().stroke(gen.accent.opacity(0.2), lineWidth: 4)
                    Circle().trim(from: 0, to: fraction)
                        .stroke(gen.accent, style: .init(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    PokeBall(size: 30, top: gen.accent)
                }
                .frame(width: 44, height: 44)

                VStack(spacing: 0) {
                    Text(gen.shortName).font(.caption.weight(.bold))
                    Text(gen.id == "all" ? "All Gens" : gen.numeral)
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 76)
            .padding(.vertical, 10)
            .background {
                // Opaque, so Pokémon roaming the background pass behind it.
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(gen.accent.opacity(active ? 0.16 : 0)))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(active ? gen.accent : .clear, lineWidth: 2)
            }
            .foregroundStyle(.primary)
        }
        .buttonStyle(PocketPressStyle())
        .accessibilityLabel("\(gen.label), \(caught) of \(gen.range.count) caught")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Binder

/// One binder page, or two side by side with ring binding between them.
private struct BinderSpread: View {
    let pokemon: [Pokemon], perPage: Int, spread: Bool
    let collection: [Int: OwnedCard]
    let onSelect: (Pokemon) -> Void

    var body: some View {
        HStack(spacing: 0) {
            page(Array(pokemon.prefix(perPage)))
            if spread {
                rings
                page(Array(pokemon.dropFirst(perPage)))
            }
        }
        .padding(14)
        .padding(.leading, spread ? 0 : 10)
        .background(alignment: .leading) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .shadow(color: .black.opacity(0.08), radius: 20, y: 10)
            if !spread { punchHoles.padding(.leading, 8) }
        }
    }

    private func page(_ items: [Pokemon]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 10) {
            ForEach(items) { p in
                Button { onSelect(p) } label: { Pocket(pokemon: p, owned: collection[p.id]) }
                    .buttonStyle(PocketPressStyle())
            }
            // Keep the 4×4 shape on a part-filled last page.
            ForEach(items.count..<perPage, id: \.self) { _ in
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.quaternarySystemFill))
                        .aspectRatio(5 / 7, contentMode: .fit)
                    Text(" ").font(.caption.bold())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var punchHoles: some View {
        VStack {
            ForEach(0..<4) { _ in
                Spacer()
                Circle().fill(Color(.systemGroupedBackground)).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(.black.opacity(0.08)))
                Spacer()
            }
        }
        .accessibilityHidden(true)
    }

    private var rings: some View {
        VStack(spacing: 0) {
            ForEach(0..<3) { _ in
                Spacer()
                Capsule().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.95), Color(white: 0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 28, height: 9)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                Spacer()
            }
        }
        .frame(width: 30)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.06), .clear], startPoint: .leading, endPoint: .trailing))
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }
}

struct PocketPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// A binder sleeve: card art if caught, a "Who's that Pokémon?" silhouette if not.
private struct Pocket: View {
    let pokemon: Pokemon
    let owned: OwnedCard?
    @Environment(ARIndex.self) private var arIndex

    var body: some View {
        let accent = Generation.of(pokemon.id).accent
        let tier = owned?.card?.tier ?? .base
        let goal = owned.map { ARGoal(owned: $0, index: arIndex, pokemonId: pokemon.id) }
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(spacing: 6) {
            ZStack {
                if owned != nil {
                    shape.fill(RadialGradient(colors: [accent.opacity(0.10), accent.opacity(0.32)], center: .center, startRadius: 4, endRadius: 80))
                } else {
                    shape.fill(Color(.tertiarySystemFill))
                }
                if let image = owned?.card?.imageUrl {
                    AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                        .padding(3)
                } else {
                    Sprite(url: pokemon.spriteURL, silhouette: owned == nil).padding(8)
                }
            }
            .aspectRatio(5 / 7, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                // Sleeve gloss.
                shape.fill(LinearGradient(colors: [.white.opacity(0.32), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            .overlay {
                if owned != nil {
                    // The card's rarity at a glance; plain cards keep the region colour.
                    if tier > .base { shape.strokeBorder(tier.border, lineWidth: tier.lineWidth) } else { shape.strokeBorder(accent, lineWidth: 2) }
                } else {
                    shape.strokeBorder(Color(.separator), style: .init(lineWidth: 1, dash: [4, 3]))
                }
            }
            .overlay(alignment: .topLeading) {
                Text(pokemon.dex).font(.system(size: 9, weight: .heavy, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                if owned != nil { PokeBall(size: 16).padding(5).shadow(color: .black.opacity(0.25), radius: 2, y: 1) }
            }
            .overlay(alignment: .bottomLeading) {
                if let goal { GoalBadge(goal: goal, card: owned?.card).padding(4) }
            }
            .overlay(alignment: .bottomTrailing) {
                if owned?.card?.imageUrl != nil {
                    Sprite(url: pokemon.spriteURL).frame(width: 28, height: 28)
                        .background(.regularMaterial, in: .circle).padding(4)
                }
            }

            Text(pokemon.name)
                .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(owned == nil ? .secondary : .primary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pokemon.name), \(pokemon.dex), \(owned == nil ? "missing" : "collected")\(goal?.spoken ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - AR goal

/// Corner badge on a caught pocket: the AR is in, there's an AR to upgrade to, or no AR exists (maxed).
private struct GoalBadge: View {
    let goal: ARGoal
    let card: CardOption?

    var body: some View {
        switch goal {
        case .gotAR:
            if let card { RarityChip(card: card) }
        case .maxed:
            Label("MAX", systemImage: "crown.fill")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 8, weight: .black, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RarityTier.ultra.border, in: .capsule)
                .foregroundStyle(Color.pokeInk)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        case .upgrade:
            HStack(spacing: 3) {
                if let card { RarityChip(card: card) }
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white, Color.black.opacity(0.55))
            }
        case .unknown:
            if let card { RarityChip(card: card) }
        }
    }
}

extension ARGoal {
    var spoken: String {
        switch self {
        case .gotAR: ", AR collected"
        case .maxed: ", maxed, no AR exists"
        case .upgrade: ", an AR exists to upgrade to"
        case .unknown: ""
        }
    }
}

/// Progress toward an AR in every pocket, with a button to re-check every caught Pokémon.
private struct ARGoalBar: View {
    let owned: [Int: OwnedCard]
    @Environment(ARIndex.self) private var arIndex
    @Environment(CollectionStore.self) private var store

    var body: some View {
        let goals = owned.map { ARGoal(owned: $0.value, index: arIndex, pokemonId: $0.key) }
        let got = goals.filter { $0 == .gotAR }.count, maxed = goals.filter { $0 == .maxed }.count
        let upgrade = goals.filter { $0 == .upgrade }.count

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AR GOAL").font(.caption2.weight(.heavy)).tracking(0.8).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    stat("\(got)", "AR", RarityTier.art.border)
                    stat("\(maxed)", "maxed", RarityTier.ultra.border)
                    stat("\(upgrade)", "to upgrade", AnyShapeStyle(Color.secondary))
                }
            }
            Spacer(minLength: 0)
            if case .scanning(let done, let total) = arIndex.progress {
                VStack(spacing: 2) {
                    ProgressView(value: Double(done), total: Double(max(total, 1))).frame(width: 70)
                    Text("Checking \(done)/\(total)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            } else {
                Button { Task { await arIndex.scan(store, force: true) } } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .font(.caption.bold())
                .secondaryButton()
                .accessibilityHint("Checks every caught Pokémon again for AR printings")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .card(20)
    }

    private func stat(_ value: String, _ label: String, _ style: AnyShapeStyle) -> some View {
        HStack(spacing: 4) {
            Circle().fill(style).frame(width: 9, height: 9)
            Text(value).font(.subheadline.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
