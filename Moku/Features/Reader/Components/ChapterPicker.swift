import SwiftUI

struct ChapterPicker: View {
    let model: ReaderViewModel
    @Binding var filter: String
    @Binding var pickerOpen: Bool

    var body: some View {
        VStack(spacing: 12) {
            sheetHeader("Chapters") { pickerOpen = false }
            TextField("Filter chapters", text: $filter).textFieldStyle(.roundedBorder).padding(
                .horizontal)
            ScrollViewReader { proxy in
                List(
                    model.details.chapters.filter {
                        filter.isEmpty || $0.label.localizedCaseInsensitiveContains(filter)
                            || ($0.scanlator?.localizedCaseInsensitiveContains(filter) ?? false)
                            || ($0.number.map { String($0) }?.contains(filter) ?? false)
                    }
                ) { chapter in
                    Button {
                        model.selectChapter(chapter.id)
                        pickerOpen = false
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(chapter.label)
                                if let scanlator = chapter.scanlator {
                                    Text(scanlator).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if chapter.id == model.chapterID { PhosphorIcon("Check", size: 18) }
                        }.foregroundStyle(
                            chapter.id == model.chapterID ? NavigationStyle.accent : .primary
                        )
                        .opacity(chapter.completed && chapter.id != model.chapterID ? 0.5 : 1)
                    }.id(chapter.id).listRowBackground(Color.clear)
                }.listStyle(.plain)
                    .onAppear { proxy.scrollTo(model.chapterID, anchor: .center) }
            }
        }.background(NavigationStyle.background).presentationDragIndicator(.visible)
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
