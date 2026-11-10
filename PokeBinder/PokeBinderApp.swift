import SwiftUI

@main
struct PokeBinderApp: App {
    @State private var store = CollectionStore()
    @State private var arIndex = ARIndex()

    var body: some Scene {
        WindowGroup {
            BinderView()
                .environment(store)
                .environment(arIndex)
                .tint(.pokeRed)
                .fontDesign(.rounded)
        }
    }
}
