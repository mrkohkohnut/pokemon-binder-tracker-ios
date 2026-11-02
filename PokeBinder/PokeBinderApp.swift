import SwiftData
import SwiftUI

@main
struct PokeBinderApp: App {
    var body: some Scene {
        WindowGroup {
            BinderView()
                .tint(.pokeRed)
                .fontDesign(.rounded)
                // The Pokédex palette is designed for light surfaces.
                .preferredColorScheme(.light)
        }
        // Syncs via the iCloud container in PokeBinder.entitlements.
        .modelContainer(for: BinderEntry.self)
    }
}
