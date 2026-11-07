import SwiftUI

extension CollectionStore.SyncStatus {
    var symbol: String {
        switch self {
        case .off: "icloud.slash"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .synced: "checkmark.icloud"
        case .failed: "exclamationmark.icloud"
        }
    }

    var label: String {
        switch self {
        case .off: "Not syncing"
        case .syncing: "Syncing…"
        case .synced: "Synced"
        case .failed(let message): message
        }
    }
}

/// Link phones with a sync code. Syncs through the Mac mini at pokemon.kohkohnut.ing by default.
struct SyncView: View {
    @Environment(CollectionStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var enteredCode = ""
    @State private var working = false

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    TextField(CollectionStore.defaultServer, text: $store.serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Sync server")
                } footer: {
                    if store.serverURL != CollectionStore.defaultServer {
                        Button("Use \(CollectionStore.defaultServer)") { store.serverURL = CollectionStore.defaultServer }
                    } else {
                        Text("Your Mac mini keeps the shared binder. It needs to be on for phones to sync.")
                    }
                }

                if store.isAutomatic {
                    Section {
                        Label("Syncing automatically", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.pokeGreen)
                    } footer: {
                        Text("Every phone with this build shares your binder through your Mac mini. No code needed.")
                    }
                } else if CollectionStore.automaticCode != nil {
                    Section {
                        Button { run { await store.useAutomaticSync() } } label: {
                            Label("Use automatic sync", systemImage: "arrow.triangle.2.circlepath")
                        }
                    } footer: {
                        Text("Joins the binder your other phones share automatically. Cards caught on this phone are kept.")
                    }
                }

                if let code = store.syncCode {
                    if !store.isAutomatic {
                    Section {
                        Text(grouped(code))
                            .font(.title3.monospaced().bold())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity)
                        ShareLink(item: code) { Label("Share code", systemImage: "square.and.arrow.up") }
                        Button { UIPasteboard.general.string = code } label: { Label("Copy code", systemImage: "doc.on.doc") }
                    } header: {
                        Text("Your sync code")
                    } footer: {
                        Text("Enter this on your other phone. Anyone with the code can see and edit your binder, so keep it private.")
                    }
                    }

                    Section {
                        LabeledContent("Status") {
                            Label(store.status.label, systemImage: store.status.symbol)
                                .foregroundStyle(statusColor)
                        }
                        Button("Sync now") { Task { await store.pull() } }
                        Button("Stop syncing on this phone", role: .destructive) { store.unlink() }
                    }
                } else {
                    Section {
                        Button {
                            run { await store.createSyncCode() }
                        } label: { Label("Start syncing this binder", systemImage: "plus.circle.fill") }
                    } footer: {
                        Text("Do this on the phone that has your cards. It makes a sync code to enter on your other phone.")
                    }

                    Section {
                        TextField("XXXX-XXXX-XXXX-XXXX-XXXX", text: $enteredCode)
                            .font(.body.monospaced())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        Button("Link this phone") { run { await store.link(code: enteredCode) } }
                            .disabled(enteredCode.filter { $0.isLetter || $0.isNumber }.count < 20)
                    } header: {
                        Text("Already have a code?")
                    } footer: {
                        Text("Cards caught on this phone are kept and added to the shared binder.")
                    }

                    if case .failed(let message) = store.status {
                        Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    }
                }
            }
            .disabled(working)
            .overlay { if working { ProgressView() } }
            .navigationTitle("Sync binder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private var statusColor: Color {
        switch store.status {
        case .failed: .red
        case .synced: .pokeGreen
        default: .secondary
        }
    }

    private func run(_ action: @escaping () async -> Void) {
        working = true
        Task { await action(); working = false }
    }

    private func grouped(_ code: String) -> String {
        stride(from: 0, to: code.count, by: 4).map { start in
            let begin = code.index(code.startIndex, offsetBy: start)
            return String(code[begin..<(code.index(begin, offsetBy: 4, limitedBy: code.endIndex) ?? code.endIndex)])
        }.joined(separator: "-")
    }
}
