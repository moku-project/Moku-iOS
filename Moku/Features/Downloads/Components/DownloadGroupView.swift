import SwiftUI

/// One title in the downloads list: a disclosure row whose children are its chapters.
struct DownloadGroupView: View {
    let group: DownloadGroup
    let model: DownloadsViewModel
    let section: DownloadsSection
    var selection: Binding<Set<String>>? = nil
    @Binding var expanded: Bool

    private var queuedCount: Int { group.entries.filter { $0.status == .queued }.count }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            if group.failures > 0 {
                Button("Retry \(group.failures) Failed", systemImage: "arrow.clockwise") {
                    model.retry(titleID: group.id)
                }
                .font(.subheadline)
                .accessibilityIdentifier("downloads.retryAll.\(group.id)")
            }
            ForEach(group.entries) { entry in chapterRow(entry) }
        } label: {
            header.accessibilityIdentifier("downloads.group.\(group.id)")
        }
        .accessibilityValue(expanded ? "Expanded" : "Collapsed")
        .listRowBackground(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 12) {
            CoverImage(url: group.entries.first?.coverURL, symbol: "book")
                .frame(width: 42, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            VStack(alignment: .leading, spacing: 4) {
                Text(group.title).font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(groupSummary).font(.caption)
                    .foregroundStyle(group.failures > 0 ? .orange : .secondary)
                if let active = group.active, section == .pending {
                    ProgressView(value: active.progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.remove(group.entries)
            } label: {
                Label(section == .completed ? "Delete" : "Remove", systemImage: "trash")
            }
            if group.failures > 0 {
                Button {
                    model.retry(titleID: group.id)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }.tint(.orange)
            }
        }
        .contextMenu {
            if section != .completed {
                Button("Move to Top", systemImage: "arrow.up") {
                    model.move(titleID: group.id, toTop: true)
                }
                Button("Move to Bottom", systemImage: "arrow.down") {
                    model.move(titleID: group.id, toTop: false)
                }
                if queuedCount > 1 {
                    Button("Reverse Order", systemImage: "arrow.up.arrow.down") {
                        model.reverse(titleID: group.id)
                    }
                }
            }
            if group.failures > 0 {
                Button("Retry Failed", systemImage: "arrow.clockwise") {
                    model.retry(titleID: group.id)
                }
            }
            Button(
                section == .completed ? "Delete Downloads" : "Remove Series Downloads",
                systemImage: "trash", role: .destructive
            ) { model.remove(group.entries) }
        }
    }

    private var groupSummary: String {
        if section == .completed {
            return
                "\(counted(group.entries.count, "chapter")) · \(ByteCountFormatter.string(fromByteCount: group.entries.reduce(0) { $0 + $1.bytes }, countStyle: .file))"
        }
        if section == .pending && model.isPaused {
            return "\(counted(group.entries.count, "chapter")) · Paused"
        }
        if group.failures > 0 {
            return "\(counted(group.entries.count, "chapter")) · \(group.failures) failed"
        }
        if let active = group.active { return "\(active.chapter) · \(Int(active.progress * 100))%" }
        return "\(counted(group.entries.count, "chapter")) · Queued"
    }

    private func chapterRow(_ entry: DownloadEntry) -> some View {
        HStack(spacing: 8) {
            if let selection {
                let selected = selection.wrappedValue.contains(entry.id)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.chapter).font(.subheadline)
                if entry.status == .completed {
                    HStack(spacing: 4) {
                        Text(
                            ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
                        )
                        if let date = entry.completedAt {
                            Text("·")
                            Text(date, style: .date)
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(
                        model.isPaused && (entry.status == .downloading || entry.status == .queued)
                            ? "Paused" : entry.status.rawValue
                    )
                    .font(.caption).foregroundStyle(entry.status == .failed ? .orange : .secondary)
                    if entry.status == .downloading {
                        ProgressView(value: entry.progress)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if entry.status == .failed {
                Button("Retry", systemImage: "arrow.clockwise") { model.retry(entryID: entry.id) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Retry \(entry.title)")
                    .accessibilityIdentifier("downloads.retry.\(entry.id)")
            } else if entry.status == .completed {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                    .accessibilityLabel("Downloaded")
            }
        }
        .contentShape(Rectangle())
        .overlay {
            if let selection {
                let selected = selection.wrappedValue.contains(entry.id)
                Button {
                    if selected {
                        selection.wrappedValue.remove(entry.id)
                    } else {
                        selection.wrappedValue.insert(entry.id)
                    }
                } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.chapter)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("downloads.select.\(entry.id)")
            }
        }
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                model.remove([entry])
            } label: {
                Label(
                    entry.status == .completed ? "Delete" : "Cancel",
                    systemImage: entry.status == .completed ? "trash" : "xmark")
            }
            if entry.status == .failed {
                Button {
                    model.retry(entryID: entry.id)
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }.tint(.orange)
            }
        }
        .swipeActions(edge: .leading) {
            if entry.status == .queued {
                Button {
                    model.move(entryID: entry.id, to: .top)
                } label: {
                    Label("Move to Top", systemImage: "arrow.up.to.line")
                }.tint(NavigationStyle.accent)
            }
        }
        .contextMenu {
            if entry.status == .failed {
                Button("Retry", systemImage: "arrow.clockwise") { model.retry(entryID: entry.id) }
            }
            if entry.status == .queued {
                Button("Move to Top", systemImage: "arrow.up.to.line") {
                    model.move(entryID: entry.id, to: .top)
                }
                Button("Move Up", systemImage: "arrow.up") {
                    model.move(entryID: entry.id, to: .up)
                }
                Button("Move Down", systemImage: "arrow.down") {
                    model.move(entryID: entry.id, to: .down)
                }
                Button("Move to Bottom", systemImage: "arrow.down.to.line") {
                    model.move(entryID: entry.id, to: .bottom)
                }
            }
            Button(
                entry.status == .completed ? "Delete Download" : "Remove from Queue",
                systemImage: "trash", role: .destructive
            ) { model.remove([entry]) }
        }
    }
}
