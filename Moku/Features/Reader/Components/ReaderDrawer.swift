import SwiftUI

struct ReaderDrawer: View {
    let model: ReaderViewModel
    @Binding var downloadsOpen: Bool
    let drawer: (Bool) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reader settings").font(.body.weight(.medium))
                    Text(model.details.title).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                icon("X", label: "Close reader settings", id: "reader.drawer.close") {
                    drawer(false)
                }
            }.padding(.leading, 18).padding(.trailing, 6).padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(spacing: 24) {
                    ReaderSettingsView(
                        preferences: model.preferences, mediaID: model.details.id,
                        landscape: model.landscape)
                    Divider()
                    Button {
                        downloadsOpen = true
                    } label: {
                        HStack {
                            PhosphorIcon("Download", size: 17)
                            Text("Downloads")
                            Spacer()
                            PhosphorIcon("CaretRight", size: 14)
                        }.frame(minHeight: 44)
                    }.accessibilityIdentifier("reader.downloads")
                }.padding(18)
            }.accessibilityIdentifier("reader.drawer.scroll")
        }
        .modifier(ReaderSurface())
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.drawer")
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { drawer(false) }
    }
    private func icon(
        _ name: String, label: String, id: String, weight: String = "regular",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PhosphorIcon(name, size: 20, weight: weight).frame(width: 44, height: 44).contentShape(
                Rectangle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

}
