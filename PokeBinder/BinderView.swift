import SwiftData
import SwiftUI

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All", caught = "Caught", missing = "Missing"
    var id: String { rawValue }
}

struct BinderView: View {
    @Query private var entries: [BinderEntry]
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""
    @State private var status = StatusFilter.all
    @State private var language: CardLanguage?
    @State private var generation = Generation.all[0]
    @State private var page = 0
    @State private var selected: Pokemon?

    /// Real binders hold 9 cards a page. Wide screens (unfolded, landscape) show an open two-page spread.
    private var spread: Bool { sizeClass == .regular }
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
        let collection = BinderEntry.collection(entries)
        let filtered = matching(collection)
        let step = perPage * (spread ? 2 : 1)
        let totalSteps = max(1, (filtered.count + step - 1) / step)
        let current = min(page, totalSteps - 1)
        let shown = Array(filtered.dropFirst(current * step).prefix(step))

        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PokedexHeader(collected: collection.count, total: Pokemon.all.count)
                    filters

                    if shown.isEmpty {
                        ContentUnavailableView {
                            Label { Text("No Pokémon found") } icon: { PokeBall(size: 44) }
                        } description: { Text("Try a different name, region, or binder filter.") }
                    } else {
                        BinderSpread(pokemon: shown, perPage: perPage, spread: spread, collection: collection) { selected = $0 }
                            .gesture(DragGesture(minimumDistance: 30).onEnded { drag in
                                if drag.translation.width < -60, current < totalSteps - 1 { withAnimation(.snappy) { page = current + 1 } }
                                if drag.translation.width > 60, current > 0 { withAnimation(.snappy) { page = current - 1 } }
                            })
                        pager(current: current, total: totalSteps, count: filtered.count)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .frame(maxWidth: spread ? 1100 : 560)
                .frame(maxWidth: .infinity)
            }
            .background(PokeBallBackdrop())
            .navigationTitle("Poké Binder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.pokeRed, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                Menu {
                    Picker("Card language", selection: $language) {
                        Text("Any language").tag(CardLanguage?.none)
                        ForEach(CardLanguage.allCases) { Text($0.rawValue).tag(Optional($0)) }
                    }
                } label: {
                    Label("Card language", systemImage: language == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
            }
            .searchable(text: $query, prompt: "Name or Pokédex number")
            .onChange(of: query) { page = 0 }
            .onChange(of: status) { page = 0 }
            .onChange(of: language) { page = 0 }
            .onChange(of: generation) { page = 0 }
            .onChange(of: spread) { page = 0 }
            .sheet(item: $selected) { pokemon in
                CardStationView(pokemon: pokemon, owned: collection[pokemon.id])
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("Binder status", selection: $status) {
                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Generation.all) { gen in
                        let active = gen == generation
                        Button { generation = gen } label: {
                            HStack(spacing: 5) {
                                PokeBall(size: 13, top: active ? .pokeRed : .gray)
                                Text(gen.label).font(.caption.bold())
                            }
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(active ? Color.pokeNavy : Color.white, in: .capsule)
                            .foregroundStyle(active ? .white : Color.pokeNavy)
                            .overlay(Capsule().stroke(Color.pokeNavy.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(active ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func pager(current: Int, total: Int, count: Int) -> some View {
        HStack {
            Button { withAnimation(.snappy) { page = current - 1 } } label: { Image(systemName: "chevron.left.circle.fill").font(.title) }
                .disabled(current == 0)
                .accessibilityLabel("Previous page")
            Spacer()
            VStack(spacing: 2) {
                Text("Page \(current + 1) of \(total)").font(.subheadline.bold().monospacedDigit())
                Text("\(count) Pokémon in this view").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { withAnimation(.snappy) { page = current + 1 } } label: { Image(systemName: "chevron.right.circle.fill").font(.title) }
                .disabled(current >= total - 1)
                .accessibilityLabel("Next page")
        }
        .foregroundStyle(Color.pokeNavy)
    }
}

/// Red Pokédex lid with lights, title and a Poké Ball progress dial.
private struct PokedexHeader: View {
    let collected: Int, total: Int
    private var fraction: Double { Double(collected) / Double(total) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                PokedexLights()
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRAINER’S NATIONAL POKÉDEX").font(.caption2.bold()).tracking(1).opacity(0.8)
                    Text("\(collected) / \(total) caught").font(.title2.bold().monospacedDigit())
                    Text("\(total - collected) still to catch").font(.footnote).opacity(0.85)
                }
            }
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 9)
                Circle().trim(from: 0, to: fraction)
                    .stroke(Color.pokeYellow, style: .init(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    PokeBall(size: 26)
                    Text(fraction, format: .percent.precision(.fractionLength(1))).font(.caption.bold().monospacedDigit())
                }
            }
            .frame(width: 96, height: 96)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(LinearGradient(colors: [.pokeRed, .pokeRedDark], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    PokeBall(size: 180, top: .white).opacity(0.07).offset(x: 50, y: -60)
                }
                .clipShape(.rect(cornerRadius: 24))
                .shadow(color: .pokeRedDark.opacity(0.35), radius: 14, y: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(collected) of \(total) Pokémon caught")
    }
}

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
        .padding(spread ? 14 : 12)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(LinearGradient(colors: [.pokeNavy, Color(red: 0.05, green: 0.1, blue: 0.19)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .pokeNavy.opacity(0.35), radius: 16, y: 10)
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
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)).aspectRatio(5 / 7, contentMode: .fit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var rings: some View {
        VStack(spacing: 0) {
            ForEach(0..<3) { _ in
                Spacer()
                Capsule().fill(LinearGradient(colors: [.gray, .white, .gray], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 22, height: 10)
                Spacer()
            }
        }
        .frame(width: 34)
        .background(Color.black.opacity(0.25))
        .padding(.horizontal, 6)
        .accessibilityHidden(true)
    }
}

private struct PocketPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A plastic binder sleeve: card art if caught, a silhouette if not.
private struct Pocket: View {
    let pokemon: Pokemon
    let owned: OwnedCard?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(owned == nil ? Color.white.opacity(0.07) : Color.white.opacity(0.92))
                if let image = owned?.card?.imageUrl {
                    AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: { ProgressView().tint(.white) }
                        .padding(3)
                } else {
                    Sprite(url: pokemon.spriteURL, silhouette: owned == nil).padding(10)
                }
            }
            .aspectRatio(5 / 7, contentMode: .fit)
            .overlay {
                // Sleeve gloss.
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [.white.opacity(0.28), .clear, .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(owned == nil ? Color.white.opacity(0.18) : Color.pokeYellow,
                                  style: .init(lineWidth: owned == nil ? 1 : 2, dash: owned == nil ? [5, 4] : []))
            }
            .overlay(alignment: .topLeading) {
                Text(pokemon.dex).font(.system(size: 9, weight: .heavy, design: .rounded).monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.55), in: .capsule).foregroundStyle(.white)
                    .padding(5)
            }
            .overlay(alignment: .topTrailing) {
                if owned != nil { PokeBall(size: 16).padding(5).shadow(radius: 2) }
            }
            .overlay(alignment: .bottomTrailing) {
                if owned?.card?.imageUrl != nil {
                    Sprite(url: pokemon.spriteURL).frame(width: 28, height: 28)
                        .background(.white.opacity(0.85), in: .circle).padding(4)
                }
            }

            Text(pokemon.name).font(.caption.bold()).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(owned == nil ? Color.white.opacity(0.6) : Color.white)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pokemon.name), \(pokemon.dex), \(owned == nil ? "missing" : "collected")")
        .accessibilityAddTraits(.isButton)
    }
}
