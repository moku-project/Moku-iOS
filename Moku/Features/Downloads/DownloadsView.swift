import SwiftUI

struct DownloadsView: View {
    @State var model: DownloadsViewModel
    var isActive = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var section: DownloadsSection = .all
    @State private var history = false
    @State private var expanded: Set<String> = []
    @State private var confirmClear = false
    @AppStorage("downloads.autoRetry") private var autoRetry = false

    private var emptyDetail: String {
        if history { return "Finished and removed downloads will appear here." }
        switch section {
        case .failed: return "No failed downloads."
        case .completed: return "Downloaded chapters and episodes appear here for offline reading."
        case .all, .pending:
            return "Download chapters or episodes from a title’s page to read and watch offline."
        }
    }

    private var isEmpty: Bool { model.count(section: section, history: history) == 0 }

    var body: some View {
        List {
            if !isEmpty {
                if section == .pending {
                    Section {
                        LabeledContent {
                            Text("\(model.count(section: section, history: history)) chapters")
                        } label: {
                            Label(
                                model.isPaused ? "Paused" : queueStatus,
                                systemImage: model.isPaused ? "pause.circle" : "arrow.down.circle")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.groups(section: section, history: history)) { group in
                    DownloadGroupView(
                        group: group, model: model, section: section,
                        expanded: Binding(
                            get: { expanded.contains(group.id) },
                            set: { open in
                                if open { expanded.insert(group.id) } else { expanded.remove(group.id) }
                            }))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("downloads.scroll")
        .overlay {
            if isEmpty {
                ContentUnavailableView {
                    Label(
                        history ? "No Download History" : "No \(section == .all ? "" : section.rawValue + " ")Downloads",
                        systemImage: history ? "clock.arrow.circlepath" : section.systemImage)
                } description: {
                    Text(emptyDetail)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Picker("Download status", selection: $section) {
                ForEach(DownloadsSection.allCases) { choice in
                    Text(choice.rawValue).tag(choice)
                        .accessibilityIdentifier("downloads.\(choice.rawValue.lowercased())")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("downloads.status")
            .padding(.horizontal, NavigationStyle.pagePadding)
            .padding(.vertical, 8)
            .onChange(of: section) { _, _ in expanded = [] }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { toolsMenu }
        }
        .task(id: isActive && scenePhase == .active) {
            guard isActive && scenePhase == .active else { return }
            model.autoRetry = autoRetry
            while !Task.isCancelled {
                await model.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        .refreshable { await model.refresh() }
        .onChange(of: autoRetry) { _, value in model.autoRetry = value }
        .onChange(of: model.autoRetry) { _, value in autoRetry = value }
        .alert("Downloads", isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })) {
            Button("OK") { model.notice = nil }
        } message: { Text(model.notice ?? "") }
        .confirmationDialog(
            "Clear \(section.rawValue.lowercased()) downloads?",
            isPresented: $confirmClear, titleVisibility: .visible
        ) {
            Button("Clear \(section.rawValue.lowercased())", role: .destructive) {
                model.clear(section: section, history: history)
            }
        } message: {
            Text(
                history && (section == .completed || section == .all)
                    ? "Remove completed records from history. Downloaded files will be kept."
                    : "Remove all \(section.rawValue.lowercased()) chapters from this view.")
        }
    }

    private var queueStatus: String {
        model.entries.contains { $0.status == .downloading } ? "Downloading" : "Waiting"
    }

    private var historyBinding: Binding<Bool> {
        Binding(get: { history }, set: { value in
            guard value != history else { return }
            history = value
            section = .all
            expanded = []
        })
    }

    private var toolsMenu: some View {
        Menu {
            Picker("View", selection: historyBinding) {
                Label("Queue", systemImage: "arrow.down.circle").tag(false)
                    .accessibilityIdentifier("downloads.queue")
                Label("History", systemImage: "clock.arrow.circlepath").tag(true)
                    .accessibilityIdentifier("downloads.history")
            }
            .pickerStyle(.inline)
            Section {
                if section == .failed {
                    Button("Retry All", systemImage: "arrow.clockwise") {
                        model.retry()
                        history = false
                        section = .pending
                        expanded = []
                    }
                    .disabled(model.count(section: .failed, history: history) == 0)
                } else {
                    Button(
                        model.isPaused ? "Resume All" : "Pause All",
                        systemImage: model.isPaused ? "play.fill" : "pause.fill"
                    ) {
                        model.isPaused.toggle()
                        if section == .pending {
                            history = false
                            expanded = []
                        }
                    }
                    .disabled(model.count(section: .pending, history: false) == 0)
                }
                Toggle(isOn: $autoRetry) {
                    Label("Auto Retry", systemImage: "repeat")
                }
            }
            if section != .completed || history {
                Section {
                    Button(
                        "Clear \(section.rawValue)", systemImage: "trash", role: .destructive
                    ) { confirmClear = true }
                    .disabled(model.count(section: section, history: history) == 0)
                }
            }
        } label: {
            Label("Download tools", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("downloads.activeView")
    }
}

extension DownloadsSection {
    var systemImage: String {
        switch self {
        case .all: "arrow.down.circle"
        case .pending: "clock"
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }
}

#if DEBUG
    #Preview("Downloads · empty") {
        NavigationStack {
            DownloadsView(model: DownloadsViewModel())
        }
    }

    #Preview("Downloads · active and failed") {
        NavigationStack {
            DownloadsView(
                model: DownloadsViewModel(entries: [
                    .init(
                        id: "preview-active", titleID: "preview-title", title: "Sample title",
                        chapter: "Chapter 12", status: .downloading, progress: 0.65),
                    .init(
                        id: "preview-failed", titleID: "preview-title", title: "Sample title",
                        chapter: "Chapter 13", status: .failed),
                    .init(
                        id: "preview-complete", titleID: "preview-history",
                        title: "Completed title",
                        chapter: "Chapter 1", status: .completed, bytes: 24_000_000,
                        completedAt: .now),
                ]))
        }
    }
#endif
