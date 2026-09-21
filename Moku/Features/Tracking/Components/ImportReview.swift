import SwiftUI

struct ImportReview: View {
    let model: TrackingViewModel
    @Binding var dryRun: Bool
    let chooseMatch: (TrackingImportItem) -> Void
    let discard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.working {
                ProgressView(model.completed > 0 ? "Imported \(model.completed)" : "Working…")
            }
            if model.items.isEmpty {
                Text("No titles in the selected lists.").foregroundStyle(.secondary)
            }
            ForEach(model.items) { item in
                HStack(spacing: 12) {
                    CoverImage(
                        url: item.match?.coverURL ?? BackendAPI.coverURL(item.remote.coverUrl),
                        symbol: "BookOpen"
                    )
                    .frame(width: 40, height: 56).clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.remote.title).font(.body).lineLimit(2)
                        Text(status(item)).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if item.state != .imported && item.state != .existing {
                        OverflowMenu {
                            if model.sourceID != nil {
                                Button("Choose match") {
                                    chooseMatch(item)
                                }
                            }
                            Button("Skip") { model.skip(item.id) }
                        } label: {
                            PhosphorIcon("DotsThree").frame(width: 44, height: 44)
                        }.disabled(model.working).accessibilityLabel(
                            "Actions for \(item.remote.title)")
                    }
                }
            }
            Toggle("Dry run", isOn: $dryRun).disabled(model.working)
            if model.items.contains(where: { $0.state == .failed }) {
                ShareLink("Export failures", item: model.failureReport).frame(minHeight: 44)
            }
            Button("Start a new import") { discard() }.disabled(model.working).frame(minHeight: 44)
        }
    }
    private func status(_ item: TrackingImportItem) -> String {
        switch item.state {
        case .pending: "Waiting to match"
        case .matched: model.sourceID == nil ? "Ready to import" : "Matched"
        case .unmatched: "Choose a match"
        case .existing: "Already saved"
        case .imported: "Imported"
        case .failed: "Failed · Retry available"
        case .skipped: "Skipped"
        }
    }

}
