import SwiftUI

struct HomeView: View {
    let store: HomeStore
    var onResume: ((HomeEntry, HomeChapter) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @AppStorage("preferences.animations") private var animations = true
    private var reduceMotion: Bool { systemReduceMotion || !animations }
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var activeSlot = 0
    @State private var presentation: HomePresentation?

    private enum HomePresentation: Identifiable {
        case details(HomeEntry)
        case history
        case pin(Int)
        var id: String {
            switch self {
            case .details(let entry): "details-\(entry.id)"
            case .history: "history"
            case .pin(let slot): "pin-\(slot)"
            }
        }
    }

    private var slot: HomeSlot { store.slots[activeSlot] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !store.isLoaded {
                    ContentSkeleton(style: .home)
                } else {
                    carousel
                    upcoming
                    recent
                    HomeActivityView(statistics: store.statistics())
                }
                if let error = store.storageError {
                    Label(error, phosphor: "Warning")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, NavigationStyle.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .firstLoadSkeleton("home", loading: !store.isLoaded, style: .home)
        .accessibilityIdentifier("home.scroll")
        .tracksNavigationScroll()
        .navigationTitle("Home")
        .task { await store.load() }
        .sheet(item: $presentation) { page in
            switch page {
            case .details(let entry):
                HomeChaptersView(entry: entry, onResume: onResume)
            case .history:
                historySheet
            case .pin(let slot):
                pinSheet(slot: slot)
            }
        }
    }

    private var historySheet: some View {
        NavigationStack {
            List(store.snapshot.sessions.sorted { $0.endedAt > $1.endedAt }) { session in
                if let entry = store.entry(session.entryID) {
                    NavigationLink {
                        HomeChaptersView(entry: entry, onResume: onResume)
                    } label: {
                        HomeRecentRow(entry: entry, session: session)
                    }.tint(.primary)
                }
            }
            .overlay {
                if store.snapshot.sessions.isEmpty {
                    ContentUnavailableView("No recent activity yet", phosphor: "Clock")
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { presentation = nil }
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func pinSheet(slot: Int) -> some View {
        NavigationStack {
            List(store.snapshot.entries) { entry in
                Button(entry.title) {
                    store.pin(entry, slot: slot)
                    presentation = nil
                }
            }
            .overlay {
                if store.snapshot.entries.isEmpty {
                    ContentUnavailableView(
                        "Nothing to pin yet", phosphor: "PushPin",
                        description: Text("Read a title to see it here."))
                }
            }
            .navigationTitle("Pin a title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentation = nil }
                }
            }
        }.preferredColorScheme(.dark)
    }

    private var carousel: some View {
        VStack(spacing: 4) {
            TabView(selection: $activeSlot) {
                ForEach(store.slots) { item in
                    HomeHeroCard(
                        slot: item, onResume: onResume, onDetails: { presentation = .details($0) }
                    )
                    .padding(.horizontal, 1)
                    .tag(item.id)
                    .contextMenu {
                        if item.id > 0 {
                            Button("Pin a title", phosphor: "PushPin") {
                                presentation = .pin(item.id)
                            }
                            if item.isPinned {
                                Button("Unpin", phosphor: "PushPinSlash") {
                                    store.pin(nil, slot: item.id)
                                }
                            }
                        }
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: typeSize.isAccessibilitySize ? 550 : 330)
            .accessibilityIdentifier("home.carousel")
            HStack(spacing: 0) {
                Button {
                    changeSlot(-1)
                } label: {
                    PhosphorIcon("CaretLeft").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous title")
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(0..<4) { index in
                        Button {
                            setSlot(index)
                        } label: {
                            Capsule().fill(
                                activeSlot == index ? Color.white : Color.gray.opacity(0.4)
                            )
                            .frame(width: activeSlot == index ? 22 : 6, height: 6)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Slot \(index + 1)")
                        .accessibilityAddTraits(activeSlot == index ? .isSelected : [])
                    }
                }
                Spacer(minLength: 0)
                Text("\(activeSlot + 1) / 4").font(.caption).foregroundStyle(
                    .secondary)
                Button {
                    changeSlot(1)
                } label: {
                    PhosphorIcon("CaretRight").frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next title")
            }.foregroundStyle(.secondary)
        }
    }

    private var upcoming: some View {
        VStack(spacing: 12) {
            HomeSectionHeading(
                title: "Up next", action: slot.entry == nil ? nil : "All chapters",
                perform: { if let entry = slot.entry { presentation = .details(entry) } })
            if let entry = slot.entry, !entry.chapters.isEmpty {
                let currentIndex =
                    entry.chapters.firstIndex { $0.id == slot.session?.chapterID } ?? 0
                VStack(spacing: 0) {
                    ForEach(Array(entry.chapters.dropFirst(currentIndex).prefix(2))) { chapter in
                        Button {
                            presentation = .details(entry)
                        } label: {
                            HomeChapterRow(
                                chapter: chapter, current: chapter.id == slot.session?.chapterID,
                                page: slot.session?.page)
                        }.buttonStyle(.plain)
                    }
                }.homePanel()
            } else {
                HomeEmptyRow(text: "No chapters to show", symbol: "ListBullets")
            }
        }
    }

    private var recent: some View {
        VStack(spacing: 12) {
            HomeSectionHeading(
                title: "Recent activity", action: store.recentSessions.isEmpty ? nil : "History",
                perform: { presentation = .history })
            if store.recentSessions.isEmpty {
                HomeEmptyRow(text: "No recent activity yet", symbol: "Clock")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.recentSessions.prefix(5))) { session in
                        if let entry = store.entry(session.entryID) {
                            Button {
                                presentation = .details(entry)
                            } label: {
                                HomeRecentRow(entry: entry, session: session)
                            }
                            .buttonStyle(.plain)
                            Divider().overlay(.white.opacity(0.04))
                        }
                    }
                }
            }
        }
    }

    private func changeSlot(_ offset: Int) { setSlot((activeSlot + offset + 4) % 4) }
    private func setSlot(_ index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { activeSlot = index }
    }
}
