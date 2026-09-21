import SwiftUI

struct HomeChaptersView: View {
    let entry: HomeEntry
    let onResume: ((HomeEntry, HomeChapter) -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(entry.title).font(.title2.weight(.semibold))
                    Text(entry.media).foregroundStyle(.secondary)
                }
                Section("Chapters") {
                    ForEach(entry.chapters) { chapter in
                        Button {
                            dismiss()
                            onResume?(entry, chapter)
                        } label: {
                            HomeChapterRow(chapter: chapter)
                        }
                        .disabled(onResume == nil)
                    }
                    if entry.chapters.isEmpty {
                        Text("No chapters to show").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Title details").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("home.details.done")
                }
            }
        }.preferredColorScheme(.dark)
    }
}
