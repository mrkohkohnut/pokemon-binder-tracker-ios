import SwiftData
import SwiftUI

@main
struct PokeBinderApp: App {
    var body: some Scene {
        WindowGroup {
            BinderView()
                .tint(.pokeRed)
        }
        // Syncs via the iCloud container in PokeBinder.entitlements.
        .modelContainer(for: BinderEntry.self)
    }
}

extension Color {
    static let pokeRed = Color(red: 0.89, green: 0.21, blue: 0.23)
    static let pokeYellow = Color(red: 1, green: 0.8, blue: 0.02)
    static let pokeNavy = Color(red: 0.09, green: 0.16, blue: 0.27)
    static let pokeGreen = Color(red: 0.18, green: 0.62, blue: 0.41)
    static let megaViolet = Color(red: 0.44, green: 0.33, blue: 0.85)
}
