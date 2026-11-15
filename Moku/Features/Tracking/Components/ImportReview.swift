import SwiftUI

/// List sections reviewing an import: one row per tracker title, with row actions.
struct ImportReview: View {
    let model: TrackingViewModel
    @Binding var dryRun: Bool
    let chooseMatch: (TrackingImportItem) -> Void
    let discard: () -> Void

    var body: some View {
        Group {
            if model.working {
                Section {
                    LabeledContent(model.completed > 0 ? "Imported \(model.completed)" : "Working…") {
                        ProgressView()
                    }
                }
            }
            Section {
                if model.items.isEmpty {
                    Text("No titles in the selected lists.").foregroundStyle(.secondary)
                }
                ForEach(model.items) { item in
                    row(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if actionable(item) {
                                Button("Skip") { model.skip(item.id) }.tint(.gray)
                                if model.sourceID != nil {
                                    Button("Match") { chooseMatch(item) }.tint(NavigationStyle.accent)
                                }
                            }
                        }
                        .contextMenu {
                            if actionable(item) {
                                if model.sourceID != nil {
                                    Button("Choose Match", systemImage: "magnifyingglass") { chooseMatch(item) }
                                }
                                Button("Skip", systemImage: "forward") { model.skip(item.id) }
                            }
                        }
                }
            } header: {
                Text("\(model.items.count) titles")
            }
            Section {
                Toggle("Dry Run", isOn: $dryRun).disabled(model.working)
                if model.items.contains(where: { $0.state == .failed }) {
                    ShareLink("Export Failures", item: model.failureReport)
                }
                Button("Start a New Import", role: .destructive) { discard() }
                    .disabled(model.working)
            } footer: {
                Text("A dry run counts what would be imported without changing your library. Swipe a title to skip it or choose its match.")
            }
        }
    }

    private func actionable(_ item: TrackingImportItem) -> Bool {
        item.state != .imported && item.state != .existing && !model.working
    }

    private func row(_ item: TrackingImportItem) -> some View {
        HStack(spacing: 12) {
            CoverImage(
                url: item.match?.coverURL ?? BackendAPI.coverURL(item.remote.coverUrl),
                symbol: "BookOpen"
            )
            .frame(width: 40, height: 56).clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.remote.title).font(.body).lineLimit(2)
                Text(status(item)).font(.subheadline)
                    .foregroundStyle(item.state == .failed || item.state == .unmatched ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let symbol = symbol(item) {
                Image(systemName: symbol).foregroundStyle(.secondary).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(actionable(item) ? "Swipe or long press for actions" : "")
    }

    private func symbol(_ item: TrackingImportItem) -> String? {
        switch item.state {
        case .imported, .existing: "checkmark.circle.fill"
        case .matched: "checkmark.circle"
        case .failed: "exclamationmark.circle"
        default: nil
        }
    }

    private func status(_ item: TrackingImportItem) -> String {
        switch item.state {
        case .pending: "Waiting to match"
        case .matched: model.sourceID == nil ? "Ready to import" : "Matched"
        case .unmatched: item.message ?? "Choose a match"
        case .existing: "Already saved"
        case .imported: "Imported"
        case .failed: "Failed · Retry available"
        case .skipped: "Skipped"
        }
    }
}
