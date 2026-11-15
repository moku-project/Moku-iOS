import SwiftUI

/// Library updates grouped by day, as List sections. Empty and loading states are drawn by RecentView.
struct UpdateList: View {
    let model: RecentViewModel
    let updates: [RecentUpdate]
    let expanded: Set<String>
    let toggle: (String) -> Void
    let open: (MediaEntry, String?) -> Void
    let refresh: () async -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    model.refreshing
                        ? "Updating library · \(model.done)/\(model.total)"
                        : "\(Set(updates.map(\.mediaID)).count) updated titles"
                )
                .font(.subheadline).foregroundStyle(.secondary)
                if model.refreshing {
                    ProgressView(value: Double(model.done), total: Double(max(1, model.total)))
                }
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                    Button("Try Again") { Task { await refresh() } }
                        .buttonStyle(.borderless)
                }
            }
            .listRowBackground(Color.clear)
        }
        // Missing source dates stay explicitly undated rather than being invented as today.
        ForEach(days(updates.map { $0.chapter.date ?? .distantPast }), id: \.self) { day in
            Section {
                let items = updates.filter {
                    Calendar.current.isDate($0.chapter.date ?? .distantPast, inSameDayAs: day)
                }
                let titleIDs = items.map(\.mediaID).reduce(into: [String]()) {
                    if !$0.contains($1) { $0.append($1) }
                }
                ForEach(titleIDs, id: \.self) { id in
                    let bundle = items.filter { $0.mediaID == id }
                    let key = "update:\(day.timeIntervalSince1970):\(id)"
                    if let first = bundle.first {
                        bundleRow(first: first, bundle: bundle, key: key)
                        if expanded.contains(key) {
                            ForEach(bundle) { updateRow($0, nested: true) }
                        }
                    }
                }
            } header: {
                Text(RecentDayTitle.text(day))
            }
        }
    }

    private func bundleRow(first: RecentUpdate, bundle: [RecentUpdate], key: String) -> some View {
        let canDownload = !bundle.allSatisfy { $0.chapter.downloaded || model.queued.contains($0.id) }
        let unit = first.entry.media == .anime
            ? (bundle.count == 1 ? "episode" : "episodes") : (bundle.count == 1 ? "chapter" : "chapters")
        return Button {
            toggle(key)
        } label: {
            HStack(spacing: 12) {
                cover(first.entry)
                VStack(alignment: .leading, spacing: 4) {
                    Text(first.entry.title).font(.body.weight(.medium)).lineLimit(2)
                        .foregroundStyle(.primary)
                    Text("\(bundle.count) new \(unit)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded.contains(key) ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Expand \(first.entry.title) updates")
        .accessibilityValue(expanded.contains(key) ? "Expanded" : "Collapsed")
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            if canDownload {
                Button { downloadAll(bundle) } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }.tint(.accentColor)
            }
        }
        .contextMenu {
            Button("View Title", systemImage: "info.circle") { open(first.entry, nil) }
            Button(expanded.contains(key) ? "Hide Chapters" : "Show Chapters", systemImage: "list.bullet") {
                toggle(key)
            }
            Button("Download Chapters", systemImage: "arrow.down.circle") { downloadAll(bundle) }
                .disabled(!canDownload)
        }
    }

    private func downloadAll(_ bundle: [RecentUpdate]) {
        Task {
            for item in bundle where !item.chapter.downloaded && !model.queued.contains(item.id) {
                await model.act(on: item, delete: false)
            }
        }
    }

    private func updateRow(_ item: RecentUpdate, nested: Bool) -> some View {
        let queued = model.queued.contains(item.id)
        let busy = model.busy.contains(item.id)
        return HStack(spacing: 12) {
            Button {
                open(item.entry, item.chapter.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.chapter.label).font(.subheadline).foregroundStyle(.primary)
                    if item.chapter.completed {
                        Text("Read").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, nested ? 58 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Open \(item.chapter.label)")
            Button {
                Task { await model.act(on: item, delete: item.chapter.downloaded) }
            } label: {
                Group {
                    if busy {
                        ProgressView()
                    } else {
                        Image(systemName: item.chapter.downloaded
                              ? "trash" : queued ? "clock" : "arrow.down.circle")
                    }
                }
                .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(busy || (queued && !item.chapter.downloaded))
            .accessibilityLabel(
                item.chapter.downloaded
                    ? "Delete download"
                    : queued ? "Download queued" : "Download \(item.chapter.label)")
        }
        .opacity(item.chapter.completed ? 0.65 : 1)
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing) {
            if item.chapter.downloaded {
                Button {
                    Task { await model.act(on: item, delete: true) }
                } label: { Label("Delete Download", systemImage: "trash") }.tint(.red)
            } else if !queued {
                Button {
                    Task { await model.act(on: item, delete: false) }
                } label: { Label("Download", systemImage: "arrow.down.circle") }.tint(.accentColor)
            }
        }
        .contextMenu {
            Button("Open Chapter", systemImage: "book") { open(item.entry, item.chapter.id) }
            Button("View Title", systemImage: "info.circle") { open(item.entry, nil) }
        }
    }

    private func cover(_ entry: MediaEntry) -> some View {
        CoverImage(url: entry.coverURL, symbol: entry.media.symbol).frame(width: 46, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func days(_ values: [Date]) -> [Date] {
        Set(values.map { Calendar.current.startOfDay(for: $0) }).sorted(by: >)
    }
}
