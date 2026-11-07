import SwiftUI

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All", caught = "Caught", missing = "Missing"
    var id: String { rawValue }
}

struct BinderView: View {
    @Environment(CollectionStore.self) private var store
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

    /// Real binders hold 9 cards a page. Wide screens (unfolded, landscape) show an open two-page spread.
    /// Decided by measured width, not size class: foldables report compact even when wide.
    private var spread: Bool { width >= 540 }
    private let perPage = 9

    private func matching(_ collection: [Int: OwnedCard]) -> [Pokemon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        return Pokemon.all.filter { p in
            let owned = collection[p.id]
            return generation.range.contains(p.id)
                && (q.isEmpty || p.name.lowercased().contains(q) || String(format: "%04d", p.id).contains(q))
                && (status == .all || (status == .caught) == (owned != nil))
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

                    RegionBadges(collection: collection, selection: $generation)

                    Picker("Binder status", selection: $status) {
                        ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    if shown.isEmpty {
                        ContentUnavailableView {
                            Label { Text("No Pokémon found") } icon: { PokeBall(size: 52) }
                        } description: { Text("Try a different name, region, or binder filter.") }
                    } else {
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
                .frame(maxWidth: spread ? 1100 : 600)
                .frame(maxWidth: .infinity)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .background(RegionBackdrop(accent: generation.accent))
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
                while !Task.isCancelled {
                    await store.pull()
                    try? await Task.sleep(for: .seconds(15))
                }
            }
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
                CardStationView(pokemon: pokemon, owned: collection[pokemon.id]) { pendingGotcha = $0 }
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
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(active ? gen.accent.opacity(0.16) : Color(.secondarySystemGroupedBackground))
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
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 12) {
            ForEach(items) { p in
                Button { onSelect(p) } label: { Pocket(pokemon: p, owned: collection[p.id]) }
                    .buttonStyle(PocketPressStyle())
            }
            // Keep the 3×3 shape on a part-filled last page.
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
            ForEach(0..<3) { _ in
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

    var body: some View {
        let accent = Generation.of(pokemon.id).accent
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
                    shape.strokeBorder(accent, lineWidth: 2)
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
        .accessibilityLabel("\(pokemon.name), \(pokemon.dex), \(owned == nil ? "missing" : "collected")")
        .accessibilityAddTraits(.isButton)
    }
}
