import SwiftUI

@main
struct PokeBinderApp: App {
    @State private var store = CollectionStore()

    var body: some Scene {
        WindowGroup {
            BinderView()
                .environment(store)
                .tint(.pokeRed)
                .fontDesign(.rounded)
        }
    }
}
