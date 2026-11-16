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
                            if chapter.id == model.chapterID {
                                Image(systemName: "checkmark").font(.body.weight(.semibold))
                            }
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
            icon("xmark", label: "Close", id: "reader.sheet.close", action: close)
        }.padding(.horizontal, 12)
    }
    private func icon(
        _ name: String, label: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.body.weight(.semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

}
