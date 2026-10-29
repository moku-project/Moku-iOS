import SwiftUI

/// Settings › Server › Server log: the newest embedded-server output, with
/// filter, share and clear, like desktop's log viewer.
struct ServerLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []
    @State private var filter = ""
    @State private var loading = true
    @State private var confirmClear = false

    private var shown: [(offset: Int, element: String)] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(query) }
        return Array(matching.suffix(2000).enumerated())
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown, id: \.offset) { line in
                            Text(line.element)
                                .font(.caption.monospaced())
                                .foregroundStyle(tint(line.element))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(line.offset)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .overlay {
                    if loading {
                        ProgressView()
                    } else if shown.isEmpty {
                        ContentUnavailableView {
                            Text(filter.isEmpty ? "No server output yet" : "No matching lines")
                        } description: {
                            Text(filter.isEmpty ? "Output appears here once the server starts working." : "Try a different filter.")
                        }
                    }
                }
                .onChange(of: lines.count) { _, _ in
                    if let last = shown.last { proxy.scrollTo(last.offset, anchor: .bottom) }
                }
            }
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always), prompt: "Filter")
            .refreshable { await load() }
            .navigationTitle("Server log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: ServerLog.shared.url) { PhosphorIcon("Export") }
                        .accessibilityLabel("Share server log")
                    Menu {
                        Button("Copy all", phosphor: "Copy") {
                            UIPasteboard.general.string = shown.map(\.element).joined(separator: "\n")
                            Toaster.shared.show("Copied server log")
                        }
                        Button("Refresh", phosphor: "ArrowClockwise") { Task { await load() } }
                        Button("Clear log", phosphor: "Trash", role: .destructive) { confirmClear = true }
                    } label: { PhosphorIcon("DotsThree") }
                        .accessibilityLabel("Log actions")
                }
            }
            .confirmationDialog("Clear the server log?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear log", role: .destructive) {
                    Task {
                        await ServerLog.shared.clear()
                        await load()
                    }
                }
            }
        }
        .task { await load() }
        .accessibilityIdentifier("server.log")
    }

    private func load() async {
        let text = await ServerLog.shared.tail()
        lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        loading = false
    }

    private func tint(_ line: String) -> Color {
        let lower = line.lowercased()
        if lower.contains("error") || lower.contains("panic") || lower.contains("fatal") { return .red.opacity(0.85) }
        if lower.contains("warn") { return .orange }
        return GeneralStyle.text
    }
}
