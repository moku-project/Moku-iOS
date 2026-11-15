import SwiftUI

/// Order and visibility of the content types offered by the tab bar's content button.
struct ContentTypesSettingsView: View {
    @AppStorage("preferences.modeTabs") private var savedModes = ""
    @AppStorage("contentMode") private var mode: ContentMode = .all

    private var configuration: ModeTabConfiguration { ModeTabConfiguration(storage: savedModes) }
    private var movable: [ContentMode] { configuration.order.filter { $0 != .all } }

    var body: some View {
        List {
            Section {
                row(.all)
                ForEach(movable) { row($0) }
                    .onMove(perform: move)
            } footer: {
                Text("Drag to reorder the types the content button cycles through. All is always shown.")
            }
            Section {
                Button("Reset to Default", role: .destructive) { savedModes = "" }
                    .disabled(savedModes.isEmpty || configuration == ModeTabConfiguration())
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(NavigationStyle.background.ignoresSafeArea())
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Content Types")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("settings.contentTypes")
    }

    private func row(_ item: ContentMode) -> some View {
        Toggle(isOn: Binding(
            get: { !configuration.hidden.contains(item) },
            set: { _ in update { $0.toggle(item) } }
        )) {
            Label(item.title, systemImage: item.systemImage)
        }
        .disabled(item == .all)
        .moveDisabled(item == .all)
        .accessibilityIdentifier("settings.contentTypes.\(item.rawValue)")
    }

    private func move(from source: IndexSet, to destination: Int) {
        let list = movable
        guard let from = source.first else { return }
        let target = list[min(list.count - 1, destination > from ? destination - 1 : destination)]
        update { $0.move(list[from], to: target) }
    }

    private func update(_ change: (inout ModeTabConfiguration) -> Void) {
        var next = configuration
        change(&next)
        savedModes = next.storage
        if !next.visible.contains(mode) { mode = .all }
    }
}

#if DEBUG
    #Preview {
        NavigationStack { ContentTypesSettingsView() }
    }
#endif
