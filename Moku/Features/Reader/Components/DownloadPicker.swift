import SwiftUI

struct DownloadPicker: View {
    let model: ReaderViewModel
    @Binding var nextCount: Int
    @Binding var downloadsOpen: Bool
    let queue: ([String]) -> Void

    var body: some View {
        let remaining = Array(model.details.chapters.dropFirst(model.chapterIndex + 1)).filter {
            !$0.downloaded
        }
        return VStack(alignment: .leading, spacing: 16) {
            sheetHeader("Download") { downloadsOpen = false }
            Button("This chapter") { queue([model.chapterID]) }
                .disabled(model.chapter?.downloaded == true)
            HStack {
                Button("Next chapters") { queue(Array(remaining.prefix(nextCount)).map(\.id)) }
                Spacer()
                Stepper("\(nextCount)", value: $nextCount, in: 1...max(1, remaining.count))
                    .fixedSize().accessibilityLabel("Number of chapters")
            }.disabled(remaining.isEmpty)
            Button("All remaining (\(remaining.count))") { queue(remaining.map(\.id)) }.disabled(
                remaining.isEmpty)
            Spacer()
        }.buttonStyle(.bordered).disabled(model.downloadBusy).padding(20)
            .background(NavigationStyle.background).presentationDetents([.medium])
    }
    private func sheetHeader(_ title: String, close: @escaping () -> Void) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            icon("X", label: "Close", id: "reader.sheet.close", action: close)
        }.padding(.horizontal, 12)
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
