import SwiftUI

extension Color {
    static let pokeRed = Color(red: 0.89, green: 0.21, blue: 0.23)
    static let pokeRedDark = Color(red: 0.66, green: 0.09, blue: 0.15)
    static let pokeYellow = Color(red: 1, green: 0.8, blue: 0.02)
    static let pokeBlue = Color(red: 0.17, green: 0.42, blue: 0.69)
    static let pokeNavy = Color(red: 0.09, green: 0.16, blue: 0.27)
    static let pokeGreen = Color(red: 0.18, green: 0.62, blue: 0.41)
    static let pokeCream = Color(red: 0.97, green: 0.95, blue: 0.91)
    static let megaViolet = Color(red: 0.44, green: 0.33, blue: 0.85)
}

/// Drawn Poké Ball: red top, white bottom, black band and button.
struct PokeBall: View {
    var size: CGFloat = 24
    var top: Color = .pokeRed

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(stops: [
                .init(color: top, location: 0), .init(color: top, location: 0.5),
                .init(color: .white, location: 0.5), .init(color: .white, location: 1),
            ], startPoint: .top, endPoint: .bottom))
            Rectangle().fill(.black).frame(height: size * 0.08)
            Circle().fill(.white).frame(width: size * 0.34).overlay(Circle().stroke(.black, lineWidth: size * 0.07))
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().stroke(.black, lineWidth: size * 0.07))
    }
}

/// The Pokédex's big blue lens and three indicator lights.
struct PokedexLights: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.85, blue: 1), .pokeBlue], center: .topLeading, startRadius: 2, endRadius: 30))
                .frame(width: 40, height: 40)
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            ForEach([Color.red, .pokeYellow, .pokeGreen], id: \.self) { color in
                Circle().fill(color).frame(width: 11, height: 11).overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Faint Poké Ball watermark behind content.
struct PokeBallBackdrop: View {
    var body: some View {
        Color.pokeCream
            .overlay(alignment: .bottomTrailing) {
                PokeBall(size: 320, top: .pokeRed.opacity(0.5)).opacity(0.06).offset(x: 90, y: 60)
            }
            .ignoresSafeArea()
    }
}

struct Sprite: View {
    let url: URL
    var silhouette = false

    var body: some View {
        AsyncImage(url: url) { image in
            if silhouette {
                // "Who's that Pokémon?" for pockets still to catch.
                image.resizable().interpolation(.none).scaledToFit().colorMultiply(.black).opacity(0.35)
            } else {
                image.resizable().interpolation(.none).scaledToFit()
            }
        } placeholder: { Color.clear }
    }
}

struct Tag: View {
    let text: String, color: Color
    var body: some View {
        Text(text).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.15), in: .capsule).foregroundStyle(color)
    }
}
