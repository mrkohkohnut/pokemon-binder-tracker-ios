import SwiftUI

enum StatusFilter: String, CaseIterable, Identifiable {
    case all = "All", caught = "Caught", missing = "Missing"
    var id: String { rawValue }
}

struct BinderView: View {
    @Environment(CollectionStore.self) private var store
    @State private var query = ""
    @State private var status = StatusFilter.all
    @State private var language: CardLanguage?
    @State private var generation = Generation.all[0]
    @State private var page = 0
    @State private var selected: Pokemon?

    private let pageSize = 16
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    private var filtered: [Pokemon] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "#", with: "")
        return Pokemon.all.filter { p in
            let owned = store.owned[p.id]
            return generation.range.contains(p.id)
                && (q.isEmpty || p.name.lowercased().contains(q) || String(format: "%04d", p.id).contains(q))
                && (status == .all || (status == .caught) == (owned != nil))
                && (language == nil || owned?.language == language)
        }
    }

    var body: some View {
        let filtered = filtered
        let totalPages = max(1, (filtered.count + pageSize - 1) / pageSize)
        let current = min(page, totalPages - 1)
        let pagePokemon = filtered.dropFirst(current * pageSize).prefix(pageSize)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ProgressHeader(collected: store.owned.count, total: Pokemon.all.count)
                    filters
                    HStack {
                        Text("\(filtered.count) Pokémon in this view").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button { page = current - 1 } label: { Image(systemName: "chevron.left") }
                            .disabled(current == 0)
                        Text("Page \(current + 1) of \(totalPages)").font(.footnote.monospacedDigit())
                        Button { page = current + 1 } label: { Image(systemName: "chevron.right") }
                            .disabled(current >= totalPages - 1)
                    }
                    if pagePokemon.isEmpty {
                        ContentUnavailableView("No Pokémon found", systemImage: "magnifyingglass",
                                               description: Text("Try a different name, region, or binder filter."))
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(pagePokemon) { pokemon in
                                Button { selected = pokemon } label: { Pocket(pokemon: pokemon, owned: store.owned[pokemon.id]) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .background(Color.pokeNavy.gradient, in: .rect(cornerRadius: 18))
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Poké Binder")
            .searchable(text: $query, prompt: "Name or Pokédex number")
            .onChange(of: query) { page = 0 }
            .sheet(item: $selected) { pokemon in
                CardStationView(pokemon: pokemon).environment(store)
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 10) {
            Picker("Binder status", selection: $status) {
                ForEach(StatusFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: status) { page = 0 }

            HStack {
                Picker("Region", selection: $generation) {
                    ForEach(Generation.all) { Text($0.label).tag($0) }
                }
                .onChange(of: generation) { page = 0 }
                Spacer()
                Picker("Card language", selection: $language) {
                    Text("Any language").tag(CardLanguage?.none)
                    ForEach(CardLanguage.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .onChange(of: language) { page = 0 }
            }
        }
    }
}

private struct ProgressHeader: View {
    let collected: Int, total: Int
    private var fraction: Double { Double(collected) / Double(total) }

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 10)
                Circle().trim(from: 0, to: fraction)
                    .stroke(Color.pokeYellow, style: .init(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(fraction, format: .percent.precision(.fractionLength(1))).font(.headline)
                    Text("complete").font(.caption2)
                }
            }
            .frame(width: 92, height: 92)

            VStack(alignment: .leading, spacing: 4) {
                Text("Binder progress").font(.caption).textCase(.uppercase).opacity(0.8)
                Text("\(collected) / \(total)").font(.title.bold().monospacedDigit())
                Text("\(total - collected) Pokémon still to catch").font(.footnote).opacity(0.8)
            }
            Spacer()
        }
        .foregroundStyle(.white)
        .padding()
        .background(LinearGradient(colors: [.pokeRed, Color(red: 0.72, green: 0.11, blue: 0.17)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}

private struct Pocket: View {
    let pokemon: Pokemon
    let owned: OwnedCard?

    var body: some View {
        VStack(spacing: 2) {
            HStack {
                Text(pokemon.dex).font(.system(size: 9, weight: .semibold).monospacedDigit())
                Spacer()
                if owned != nil { Image(systemName: "checkmark.circle.fill").font(.caption2).foregroundStyle(Color.pokeGreen) }
            }
            ZStack(alignment: .bottomTrailing) {
                if let image = owned?.card?.imageUrl {
                    AsyncImage(url: image) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                    Sprite(url: pokemon.spriteURL).frame(width: 22, height: 22)
                } else {
                    Sprite(url: pokemon.spriteURL).opacity(owned == nil ? 0.45 : 1)
                }
            }
            .frame(height: 64)
            Text(pokemon.name).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            Text(owned.map { "\($0.language.rawValue) · \($0.card?.setCode ?? "Saved")" } ?? "Open pocket")
                .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(owned == nil ? Color(.secondarySystemBackground) : Color(.systemBackground), in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(owned == nil ? Color.secondary.opacity(0.3) : Color.pokeGreen,
                              style: .init(lineWidth: 1.5, dash: owned == nil ? [4] : []))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pokemon.name), \(owned == nil ? "missing" : "collected")")
    }
}

struct Sprite: View {
    let url: URL
    var body: some View {
        AsyncImage(url: url) { $0.resizable().interpolation(.none).scaledToFit() } placeholder: { Color.clear }
    }
}
