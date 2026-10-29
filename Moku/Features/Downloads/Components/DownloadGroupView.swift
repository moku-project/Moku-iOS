import SwiftUI

struct DownloadGroupView: View {
    let group: DownloadGroup
    let model: DownloadsViewModel
    let section: DownloadsSection
    let expanded: Bool
    let reduceMotion: Bool
    let toggle: () -> Void
    var body: some View {
        let open = expanded
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    CoverImage(url: group.entries.first?.coverURL, symbol: "BookOpen")
                        .frame(width: 42, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.title).font(.subheadline.weight(.semibold)).foregroundStyle(
                            .primary
                        ).multilineTextAlignment(.leading)
                        Text(groupSummary(group)).font(.caption).foregroundStyle(
                            group.failures > 0 ? .orange : .secondary)
                        if let active = group.active, section == .pending {
                            ProgressView(value: active.progress).tint(NavigationStyle.accent)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    PhosphorIcon("CaretDown", size: 12)
                        .rotationEffect(.degrees(open ? 180 : 0)).foregroundStyle(.secondary)
                }.padding(14).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("downloads.group.\(group.id)")
                .accessibilityValue(open ? "Expanded" : "Collapsed")
                .contextMenu {
                    if section != .completed {
                        Button("Move to top", phosphor: "ArrowUp") { model.move(titleID: group.id, toTop: true) }
                        Button("Move to bottom", phosphor: "ArrowDown") { model.move(titleID: group.id, toTop: false) }
                    }
                    if group.failures > 0 {
                        Button("Retry failed", phosphor: "ArrowClockwise") { model.retry(titleID: group.id) }
                    }
                    Button(section == .completed ? "Delete downloads" : "Remove series downloads",
                           phosphor: "Trash", role: .destructive) { model.remove(group.entries) }
                }
            if open {
                Divider().overlay(.white.opacity(0.04))
                if group.failures > 0 {
                    HStack {
                        Text("\(group.failures) failed").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        retryButton("Retry all", identifier: "downloads.retryAll.\(group.id)") {
                            model.retry(titleID: group.id)
                        }
                    }.padding(.horizontal, 14)
                }
                ForEach(group.entries) { entry in chapterRow(entry) }
            }
        }
    }

    private func groupSummary(_ group: DownloadGroup) -> String {
        if section == .completed {
            return
                "\(group.entries.count) chapters · \(ByteCountFormatter.string(fromByteCount: group.entries.reduce(0) { $0 + $1.bytes }, countStyle: .file))"
        }
        if section == .pending && model.isPaused {
            return "\(group.entries.count) chapters · Paused"
        }
        if group.failures > 0 {
            return "\(group.entries.count) chapters · \(group.failures) failed"
        }
        if let active = group.active { return "\(active.chapter) · \(Int(active.progress * 100))%" }
        return "\(group.entries.count) chapters · Queued"
    }

    private func chapterRow(_ entry: DownloadEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.chapter).font(.subheadline)
                if entry.status == .completed {
                    Text(ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file))
                        .font(.caption).foregroundStyle(.secondary)
                    if let date = entry.completedAt {
                        Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text(
                        model.isPaused && (entry.status == .downloading || entry.status == .queued)
                            ? "Paused" : entry.status.rawValue
                    )
                    .font(.caption).foregroundStyle(entry.status == .failed ? .orange : .secondary)
                    if entry.status == .downloading {
                        ProgressView(value: entry.progress).tint(NavigationStyle.accent)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if entry.status == .failed {
                retryButton("Retry", identifier: "downloads.retry.\(entry.id)") {
                    model.retry(entryID: entry.id)
                }
            } else if entry.status == .completed {
                PhosphorIcon("DownloadSimple.fill").foregroundStyle(NavigationStyle.accent)
            }
        }.padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .contextMenu {
                if entry.status == .failed {
                    Button("Retry", phosphor: "ArrowClockwise") { model.retry(entryID: entry.id) }
                }
                if entry.status == .queued {
                    Button("Move to top", phosphor: "ArrowLineUp") { model.move(entryID: entry.id, to: .top) }
                    Button("Move up", phosphor: "ArrowUp") { model.move(entryID: entry.id, to: .up) }
                    Button("Move down", phosphor: "ArrowDown") { model.move(entryID: entry.id, to: .down) }
                    Button("Move to bottom", phosphor: "ArrowLineDown") { model.move(entryID: entry.id, to: .bottom) }
                }
                Button(entry.status == .completed ? "Delete download" : "Remove from queue",
                       phosphor: "Trash", role: .destructive) { model.remove([entry]) }
            }
    }

    private func retryButton(_ title: String, identifier: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Label(title, phosphor: "ArrowClockwise")
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                .overlay {
                    RoundedRectangle(cornerRadius: 5).strokeBorder(
                        .white.opacity(0.12), lineWidth: 0.5)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityIdentifier(identifier)
    }
}
