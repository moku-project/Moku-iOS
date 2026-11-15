import SwiftUI

/// Queues every missing chapter in a chosen range.
struct DownloadRangeSheet: View {
    /// Reading order, oldest first.
    let chapters: [Chapter]
    let isAnime: Bool
    let enqueue: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var from = 0
    @State private var to = 0

    private var bounds: ClosedRange<Int> { min(from, to)...max(from, to) }
    private var queueable: [String] {
        guard !chapters.isEmpty else { return [] }
        return chapters[bounds].filter(\.canQueueDownload).map(\.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    picker("From", selection: $from)
                    picker("To", selection: $to)
                } footer: {
                    let count = queueable.count
                    Text(count == 0
                         ? "Everything in this range is already downloaded or queued."
                         : "\(count) \(isAnime ? "episode" : "chapter")\(count == 1 ? "" : "s") will be queued. Downloaded and queued ones are skipped.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle("Download Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Download") {
                        enqueue(queueable)
                        dismiss()
                    }
                    .disabled(queueable.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear {
            // Start at the first unread chapter, ending ten later.
            let start = chapters.firstIndex { !$0.completed } ?? 0
            from = start
            to = min(chapters.count - 1, start + 9)
        }
    }

    private func picker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(chapters.indices, id: \.self) { index in
                Text(chapters[index].label).tag(index)
            }
        }
        .pickerStyle(.navigationLink)
    }
}
