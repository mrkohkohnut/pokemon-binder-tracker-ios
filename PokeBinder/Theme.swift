import SwiftUI

extension Color {
    static let pokeRed = Color(red: 0.93, green: 0.22, blue: 0.24)
    static let pokeRedDark = Color(red: 0.70, green: 0.08, blue: 0.16)
    static let pokeYellow = Color(red: 1, green: 0.80, blue: 0.05)
    static let pokeBlue = Color(red: 0.17, green: 0.42, blue: 0.80)
    static let pokeNavy = Color(red: 0.09, green: 0.16, blue: 0.27)
    static let pokeGreen = Color(red: 0.18, green: 0.68, blue: 0.43)
    static let megaViolet = Color(red: 0.50, green: 0.36, blue: 0.92)
    static let pokeInk = Color(red: 0.11, green: 0.12, blue: 0.16)
}

extension Generation {
    /// Signature colour per region, taken from its games.
    var accent: Color {
        switch id {
        case "kanto": Color(red: 0.93, green: 0.22, blue: 0.24)   // Red
        case "johto": Color(red: 0.87, green: 0.64, blue: 0.10)   // Gold
        case "hoenn": Color(red: 0.10, green: 0.64, blue: 0.42)   // Emerald
        case "sinnoh": Color(red: 0.88, green: 0.42, blue: 0.62)  // Pearl
        case "unova": Color(red: 0.32, green: 0.34, blue: 0.42)   // Black
        case "kalos": Color(red: 0.13, green: 0.47, blue: 0.88)   // X
        case "alola": Color(red: 0.98, green: 0.52, blue: 0.13)   // Sun
        case "galar": Color(red: 0.02, green: 0.62, blue: 0.72)   // Sword
        case "paldea": Color(red: 0.56, green: 0.30, blue: 0.86)  // Violet
        default: .pokeRed
        }
    }

    var shortName: String { id == "all" ? "National" : id.capitalized }
    var numeral: String { label.components(separatedBy: "· ").last ?? "" }

    static func of(_ pokemonId: Int) -> Generation {
        all.dropFirst().first { $0.range.contains(pokemonId) } ?? all[0]
    }
}

/// Glossy drawn Poké Ball.
struct PokeBall: View {
    var size: CGFloat = 24
    var top: Color = .pokeRed
    var bottom: Color = .white

    var body: some View {
        let band = size * 0.075
        ZStack {
            VStack(spacing: 0) {
                top.overlay(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                bottom.overlay(LinearGradient(colors: [.clear, .black.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            }
            Rectangle().fill(Color.pokeInk).frame(height: band)
            Circle().fill(Color.pokeInk).frame(width: size * 0.40)
            Circle().fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.26)
            // Specular highlight.
            Ellipse().fill(.white.opacity(0.35))
                .frame(width: size * 0.36, height: size * 0.14)
                .rotationEffect(.degrees(-30))
                .offset(x: -size * 0.2, y: -size * 0.28)
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(Color.pokeInk, lineWidth: max(1, size * 0.05)))
        .accessibilityHidden(true)
    }
}

/// Soft region-coloured glow behind the whole screen, like the Pokédex screen lighting up.
struct RegionBackdrop: View {
    var accent: Color

    var body: some View {
        Color(.systemGroupedBackground)
            .overlay(alignment: .top) {
                LinearGradient(colors: [accent.opacity(0.28), accent.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 520)
            }
            .overlay(alignment: .topTrailing) {
                PokeBall(size: 360, top: accent, bottom: accent.opacity(0.4))
                    .opacity(0.07)
                    .rotationEffect(.degrees(-18))
                    .offset(x: 140, y: -40)
            }
            .ignoresSafeArea()
            .animation(.smooth, value: accent)
    }
}

struct Sprite: View {
    let url: URL
    var silhouette = false
    var pixelated = true

    var body: some View {
        CachedImage(url: url) { image in
            if silhouette {
                // "Who's that Pokémon?" for pockets still to catch.
                // Template rendering keeps the shape and adapts to light and dark mode.
                image.resizable().renderingMode(.template).interpolation(pixelated ? .none : .high).scaledToFit()
                    .foregroundStyle(.primary.opacity(0.45))
            } else {
                image.resizable().interpolation(pixelated ? .none : .high).scaledToFit()
            }
        } placeholder: { Color.clear }
    }
}

struct Tag: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.15), in: .capsule).foregroundStyle(color)
    }
}

// MARK: - Liquid Glass with fallbacks for iOS 17–25

extension View {
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
    }

    @ViewBuilder
    func prominentButton() -> some View {
        if #available(iOS 26, *) { buttonStyle(.glassProminent) } else { buttonStyle(.borderedProminent) }
    }

    @ViewBuilder
    func secondaryButton() -> some View {
        if #available(iOS 26, *) { buttonStyle(.glass) } else { buttonStyle(.bordered) }
    }

    /// Grouped "card" surface used across the app.
    func card(_ radius: CGFloat = 24) -> some View {
        background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: radius, style: .continuous))
    }
}
