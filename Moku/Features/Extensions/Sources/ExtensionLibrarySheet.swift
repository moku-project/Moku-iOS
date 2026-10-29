import SwiftUI

/// Desktop per-extension library: the saved titles that come from one source,
/// and bulk migration of all of them to another installed source. Each title is
/// matched by searching the target and keeping only a confident title match;
/// the rest are listed so you can switch them one by one from Details.
struct ExtensionLibrarySheet: View {
    let source: SourceExtension
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [MigrateSheet.Source] = []
    @State private var target: MigrateSheet.Source?
    @State private var plan: [Item] = []
    @State private var phase: Phase = .idle
    @State private var confirm = false
    @State private var error: String?

    private enum Phase: Equatable { case idle, matching(Int), ready, moving(Int), done }

    struct Item: Identifiable {
        let entry: MediaEntry
        var match: MediaEntry?
        var state: State = .pending
        enum State { case pending, matched, excluded, unmatched, moved, failed }
        var id: String { entry.id }
    }

    private var titles: [MediaEntry] {
        library.entries.filter { $0.extensionID == source.packageName }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    private var busy: Bool {
        if case .matching = phase { return true }
        if case .moving = phase { return true }
        return false
    }
    private var ready: [Item] { plan.filter { $0.state == .matched } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("\(titles.count) saved title\(titles.count == 1 ? "" : "s") from \(source.displayName).")
                        .font(.subheadline).foregroundStyle(GeneralStyle.label)
                }
                Section("Move all to another source") {
                    Picker("Move to", selection: $target) {
                        Text("Choose a source").tag(MigrateSheet.Source?.none)
                        ForEach(targets) { item in
                            Text("\(item.displayName) · \(GeneralPreferences.languageName(GeneralPreferences.canonicalLanguage(item.lang)))")
                                .tag(MigrateSheet.Source?.some(item))
                        }
                    }
                    .disabled(busy)
                    switch phase {
                    case .matching(let done):
                        ProgressView(value: Double(done), total: Double(max(1, plan.count))) {
                            Text("Finding matches… \(done) of \(plan.count)").font(.footnote)
                        }
                    case .moving(let done):
                        ProgressView(value: Double(done), total: Double(max(1, ready.count + done))) {
                            Text("Moving titles… \(done) moved").font(.footnote)
                        }
                    default:
                        Button("Find matches") { Task { await match() } }
                            .disabled(target == nil || titles.isEmpty)
                    }
                    if phase == .ready, !ready.isEmpty {
                        Button("Move \(ready.count) title\(ready.count == 1 ? "" : "s")") { confirm = true }
                            .fontWeight(.semibold)
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.orange) } }
                Section(plan.isEmpty ? "Titles" : "Matches") {
                    ForEach(plan.isEmpty ? titles.map { Item(entry: $0) } : plan) { item in
                        if phase == .ready, item.state == .matched || item.state == .excluded {
                            Button { toggle(item.id) } label: { row(item) }
                                .buttonStyle(.plain)
                                .accessibilityHint(item.state == .matched ? "Leaves this title out" : "Includes this title")
                        } else {
                            row(item)
                        }
                    }
                }
                Section {
                    Text("Read progress carries over by chapter number. Downloads stay with the old source. Titles without a confident match are left alone; tap a match to leave it out.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
            .scrollContentBackground(.hidden)
            .background(NavigationStyle.background.ignoresSafeArea())
            .navigationTitle(source.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
            .task {
                await library.load()
                await loadTargets()
            }
            .onChange(of: target) { _, _ in
                plan = []
                phase = .idle
            }
            .confirmationDialog(
                "Move \(ready.count) titles to \(target?.displayName ?? "this source")?",
                isPresented: $confirm, titleVisibility: .visible
            ) {
                Button("Move titles") { Task { await move() } }
            } message: {
                Text("Each title is removed from \(source.displayName).")
            }
        }
    }

    private func row(_ item: Item) -> some View {
        HStack(spacing: 12) {
            CoverImage(url: item.entry.coverURL, symbol: item.entry.media.symbol)
                .frame(width: 36, height: 52).clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.entry.title).font(.subheadline).lineLimit(2)
                if let status = status(item) {
                    Text(status).font(.caption).foregroundStyle(item.state == .failed || item.state == .unmatched ? .orange : GeneralStyle.label)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            switch item.state {
            case .matched: PhosphorIcon("CheckCircle").foregroundStyle(NavigationStyle.accent)
            case .moved: PhosphorIcon("CheckCircle.fill").foregroundStyle(NavigationStyle.accent)
            default: EmptyView()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func status(_ item: Item) -> String? {
        switch item.state {
        case .pending: nil
        case .matched: item.match.map { "→ \($0.title)" }
        case .excluded: "Left out. Tap to include."
        case .unmatched: "No confident match"
        case .moved: "Moved"
        case .failed: "Couldn’t move. Try from Details."
        }
    }

    private func toggle(_ id: String) {
        guard let index = plan.firstIndex(where: { $0.id == id }) else { return }
        plan[index].state = plan[index].state == .matched ? .excluded : .matched
    }

    private func loadTargets() async {
        struct Response: Decodable, Sendable { let installedExtensions: [MigrateSheet.Source] }
        do {
            let response: Response = try await BackendAPI.shared.graphql(
                "{ installedExtensions { id packageName displayName lang contentType } }", requiresSourceRuntime: false)
            targets = response.installedExtensions
                .filter { $0.contentType == source.contentType && $0.packageName != source.packageName }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            if targets.isEmpty { error = "Install another \(source.media.title.lowercased()) source to move titles to." }
        } catch { self.error = "Couldn’t load sources." }
    }

    private func match() async {
        guard let target else { return }
        error = nil
        plan = titles.map { Item(entry: $0) }
        phase = .matching(0)
        for index in plan.indices {
            guard !Task.isCancelled else { break }
            let title = plan[index].entry.title
            let request = SearchRequest(query: title, options: SearchOptions(media: source.media, sourceID: target.packageName))
            let results = (try? await LiveMediaRepository.shared.search(request)) ?? []
            let best = results.max { MigrateSheet.score($0.title, title) < MigrateSheet.score($1.title, title) }
            if let best, best.externalID != nil,
               MigrateSheet.score(best.title, title) >= 0.8
                || TrackingViewModel.normalized(best.title) == TrackingViewModel.normalized(title) {
                plan[index].match = best
                plan[index].state = .matched
            } else {
                plan[index].state = .unmatched
            }
            phase = .matching(index + 1)
        }
        phase = .ready
        if ready.isEmpty { error = "No confident matches on \(target.displayName). Try another source." }
    }

    private func move() async {
        guard let target else { return }
        var moved = 0
        phase = .moving(0)
        for index in plan.indices where plan[index].state == .matched {
            guard let externalID = plan[index].match?.externalID else { continue }
            do {
                let _: IgnoredGraphQLResult = try await BackendAPI.shared.graphql(
                    "mutation { migrateMedia(fromMediaId: \(BackendAPI.literal(plan[index].entry.id)), toExtensionId: \(BackendAPI.literal(target.id)), toExternalId: \(BackendAPI.literal(externalID))) { id } }")
                plan[index].state = .moved
                moved += 1
            } catch {
                plan[index].state = .failed
            }
            phase = .moving(moved)
            // Keep sources happy; desktop paces bulk work the same way.
            try? await Task.sleep(for: .milliseconds(500))
        }
        library.invalidateServerVisibility()
        _ = await library.refreshFromServer()
        phase = .done
        Toaster.shared.show("Moved \(moved) title\(moved == 1 ? "" : "s") to \(target.displayName)",
                            kind: plan.contains { $0.state == .failed } ? .error : .success)
    }
}
