import SwiftUI

struct ReaderView: View {
    @State private var model: ReaderViewModel
    private var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("preferences.animations") private var animations = true
    @AppStorage("keybinds.reader") private var readerShortcuts = Data()
    @FocusState private var keyboardFocused: Bool
    @State private var pickerOpen = false
    @State private var downloadsOpen = false
    @State private var pageEntryOpen = false
    @State private var pageDraft = ""
    @State private var filter = ""
    @State private var nextCount = 5
    @State private var actionTask: Task<Void, Never>?
    @State private var closing = false
    @State private var drawerDrag: CGFloat = 0

    init(
        details: MediaDetails, chapterID: String, preferences: ReaderPreferences,
        repository: any ReaderRepository = LiveReaderRepository(), onClose: (() -> Void)? = nil
    ) {
        self.onClose = onClose
        _model = State(
            initialValue: ReaderViewModel(
                details: details, chapterID: chapterID,
                preferences: preferences, repository: repository))
    }
    private var motion: Bool { animations && !reduceMotion }
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                Group {
                    if model.loading {
                        ContentSkeleton(style: .reader)
                    } else if let error = model.error {
                        VStack(spacing: 16) {
                            Text(error).font(.subheadline).multilineTextAlignment(.center)
                            Button("Try again") { run { await model.load() } }
                        }.padding(24)
                    } else {
                        ReaderCanvas(
                            model: model,
                            active: scenePhase == .active && !model.drawerOpen && !pickerOpen
                                && !pageEntryOpen && !downloadsOpen,
                            reduceMotion: !motion, toggleChrome: toggleChrome
                        )
                        .ignoresSafeArea()
                    }
                }
                .firstLoadSkeleton(
                    "reader-\(model.chapterID)", loading: model.loading, style: .reader)
                if model.chromeVisible && !model.drawerOpen {
                    if model.settings.barPosition == "top" {
                        VStack {
                            topBar
                            Spacer()
                            progressBar
                        }.padding(12)
                    } else {
                        HStack {
                            if model.settings.barPosition == "right" { Spacer() }
                            sideBar
                            if model.settings.barPosition == "left" { Spacer() }
                        }.padding(12)
                    }
                }
                if let resumed = model.resumedPage, model.page == resumed, model.chromeVisible, !model.drawerOpen {
                    VStack {
                        Spacer()
                        Button { model.resumedPage = nil } label: {
                            Label("Bookmark at page \(resumed)", phosphor: "Bookmark")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .modifier(ReaderSurface())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Dismisses this notice")
                        .accessibilityIdentifier("reader.resumed")
                        .padding(.bottom, model.settings.barPosition == "top" ? 120 : 32)
                    }
                    .transition(.opacity)
                    .task(id: resumed) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation(motion ? .easeOut(duration: 0.4) : nil) { model.resumedPage = nil }
                    }
                }
                if model.drawerOpen {
                    Color.black.opacity(0.42).ignoresSafeArea()
                        .onTapGesture { drawer(false) }
                        .accessibilityLabel("Close reader settings")
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        ReaderDrawer(model: model, downloadsOpen: $downloadsOpen, drawer: drawer)
                            .frame(width: min(380, geometry.size.width * 0.88))
                            .offset(x: drawerDrag)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 24).onChanged { value in
                                    if value.startLocation.x < 24
                                        && value.translation.width > abs(value.translation.height)
                                    {
                                        drawerDrag = max(0, value.translation.width)
                                    }
                                }.onEnded { value in
                                    if value.startLocation.x < 24 && value.translation.width > 90 {
                                        drawer(false)
                                    }
                                    withAnimation(motion ? .easeOut(duration: 0.2) : nil) {
                                        drawerDrag = 0
                                    }
                                })
                    }.transition(motion ? .move(edge: .trailing) : .opacity)
                }
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                model.landscape = size.width / max(1, size.height) > 1.25
            }
        }
        .focusable().focusEffectDisabled().focused($keyboardFocused)
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
        .onAppear { keyboardFocused = true }
        .onChange(of: model.drawerOpen) { _, open in if !open { keyboardFocused = true } }
        .onChange(of: pickerOpen) { _, open in if !open { keyboardFocused = true } }
        .onChange(of: downloadsOpen) { _, open in if !open { keyboardFocused = true } }
        .preference(key: GeneralMediaPresentedKey.self, value: true)
        .foregroundStyle(Color(white: 0.9)).tint(NavigationStyle.accent)
        .preferredColorScheme(.dark).statusBarHidden(!model.chromeVisible)
        .persistentSystemOverlays(model.chromeVisible ? .visible : .hidden)
        .task(id: model.chapterID) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { run { await model.flush() } }
        }
        .onDisappear { actionTask?.cancel() }
        .recordActivity(
            entry: model.activityEntry,
            chapterID: model.chapterID, position: model.page,
            completed: !model.pages.isEmpty
                && (model.isStrip ? model.page : (model.visiblePages.max() ?? model.page))
                    == model.pages.count,
            active: !model.drawerOpen && !pickerOpen && !downloadsOpen,
            valid: model.activityReady
        )
        .sheet(isPresented: $pickerOpen) {
            ChapterPicker(model: model, filter: $filter, pickerOpen: $pickerOpen)
        }
        .sheet(isPresented: $downloadsOpen) {
            DownloadPicker(
                model: model, nextCount: $nextCount, downloadsOpen: $downloadsOpen, queue: queue)
        }
        .alert("Go to page", isPresented: $pageEntryOpen) {
            TextField("Page", text: $pageDraft).keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {}
            Button("Go") { if let page = Int(pageDraft) { model.jump(page) } }
        } message: {
            Text("1–\(model.pages.count)")
        }
        .alert(
            "Reader",
            isPresented: Binding(
                get: { model.notice != nil }, set: { if !$0 { model.notice = nil } })
        ) {
            Button("OK") { model.notice = nil }
        } message: {
            Text(model.notice ?? "")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.screen")
    }
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !model.loading, !pageEntryOpen, !pickerOpen, !downloadsOpen, !model.drawerOpen else { return .ignored }
        let values = ReaderShortcut.values(readerShortcuts)
        guard let action = ReaderShortcut.all.first(where: { ReaderShortcut.matches(values[$0.id] ?? $0.defaultValue, press: press) }) else { return .ignored }
        if press.phase == .repeat && !["pageRight", "pageLeft"].contains(action.id) { return .handled }
        switch action.id {
        case "pageRight": keyboardPage(forward: model.settings.readingDirection != "rtl")
        case "pageLeft": keyboardPage(forward: model.settings.readingDirection == "rtl")
        case "firstPage": model.jump(1)
        case "lastPage": model.jump(model.pages.count)
        case "chapterRight": model.changeChapter(forward: true)
        case "chapterLeft": model.changeChapter(forward: false)
        case "exit": close()
        case "direction": model.settings.readingDirection = model.settings.readingDirection == "ltr" ? "rtl" : "ltr"
        case "layout":
            let layouts = ["single", "double", "auto", "longstrip"]
            model.settings.pageStyle = layouts[((layouts.firstIndex(of: model.settings.pageStyle) ?? 0) + 1) % layouts.count]
        case "fullscreen": toggleChrome()
        case "settings": drawer(true)
        case "bookmark": model.toggleBookmark()
        case "scroll": model.preferences.document.behaviour.autoScroll.toggle()
        default: return .ignored
        }
        return .handled
    }
    private func keyboardPage(forward: Bool) {
        if model.settings.pageStyle == "longstrip" {
            model.jump(min(model.pages.count, max(1, model.page + (forward ? 1 : -1))))
        } else { model.navigate(forward: forward) }
    }
    private var topBar: some View {
        HStack(spacing: 0) {
            icon("X", label: "Close reader", id: "reader.close", action: close)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 26)
            Button {
                pickerOpen = true
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.details.title).font(.subheadline.weight(.medium)).lineLimit(1)
                    HStack(spacing: 5) {
                        Text(model.chapter?.label ?? "Chapter").lineLimit(1)
                        PhosphorIcon("CaretDown", size: 11)
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(
                    .leading, 12)
            }.accessibilityLabel("Select chapter").accessibilityIdentifier("reader.chapters")
            icon(
                model.bookmarked ? "Bookmark.fill" : "Bookmark", label: "Bookmark this page",
                id: "reader.bookmark"
            ) { model.toggleBookmark() }
            .foregroundStyle(model.bookmarked ? NavigationStyle.accent : Color(white: 0.8))
            icon("Sliders", label: "Reader settings", id: "reader.settings") { drawer(true) }
        }
        .padding(4).modifier(ReaderSurface()).buttonStyle(.plain)
    }
    private var progressBar: some View {
        VStack(spacing: 0) {
            Button {
                pageDraft = String(model.page)
                pageEntryOpen = true
            } label: {
                Text("\(model.page) / \(model.pages.count)").font(
                    .caption.monospacedDigit()
                )
                .frame(minHeight: 36)
            }.accessibilityIdentifier("reader.page")
            HStack(spacing: 4) {
                icon("ArrowLeft", label: "Previous", id: "reader.previous", weight: "light") {
                    model.navigate(forward: model.settings.readingDirection == "rtl")
                }.disabled(
                    model.loading
                        || (model.settings.readingDirection == "rtl"
                            ? !model.canNext : !model.canPrevious)
                )
                ReaderSlider(
                    value: Binding(get: { Double(model.page) }, set: { model.jump(Int($0)) }),
                    in: 1...Double(max(2, model.pages.count)), step: 1
                )
                .environment(
                    \.layoutDirection,
                    model.settings.readingDirection == "rtl" ? .rightToLeft : .leftToRight
                )
                .disabled(model.pages.count < 2).accessibilityLabel("Page progress")
                icon("ArrowRight", label: "Next", id: "reader.next", weight: "light") {
                    model.navigate(forward: model.settings.readingDirection != "rtl")
                }.disabled(
                    model.loading
                        || (model.settings.readingDirection == "rtl"
                            ? !model.canPrevious : !model.canNext)
                )
            }
        }.padding(.horizontal, 4).padding(.bottom, 4)
            .modifier(ReaderSurface()).buttonStyle(.plain)
    }
    private var sideBar: some View {
        VStack(spacing: 2) {
            icon("X", label: "Close reader", id: "reader.close", action: close)
            icon("CaretUp", label: "Previous chapter", id: "reader.previousChapter") {
                model.changeChapter(forward: false)
            }
            icon("BookOpen", label: "Select chapter", id: "reader.chapters") { pickerOpen = true }
            icon("CaretDown", label: "Next chapter", id: "reader.nextChapter") {
                model.changeChapter(forward: true)
            }
            Spacer(minLength: 0)
            Text("\(model.page)").font(.caption.monospacedDigit())
            icon("ArrowLeft", label: "Previous", id: "reader.previous", weight: "light") {
                model.navigate(forward: false)
            }
            icon("ArrowRight", label: "Next", id: "reader.next", weight: "light") {
                model.navigate(forward: true)
            }
            Spacer(minLength: 0)
            icon(
                model.bookmarked ? "Bookmark.fill" : "Bookmark", label: "Bookmark this page",
                id: "reader.bookmark"
            ) { model.toggleBookmark() }
            icon("Sliders", label: "Reader settings", id: "reader.settings") { drawer(true) }
        }.padding(4).modifier(ReaderSurface())
    }
    private func icon(
        _ name: String, label: String, id: String, weight: String = "regular",
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PhosphorIcon(name, size: 20, weight: weight).frame(width: 44, height: 44).contentShape(
                Rectangle())
        }
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func drawer(_ open: Bool) {
        withAnimation(motion ? .easeInOut(duration: 0.24) : nil) {
            model.drawerOpen = open
            model.chromeVisible = true
        }
    }
    private func toggleChrome() {
        withAnimation(motion ? .easeInOut(duration: 0.18) : nil) { model.chromeVisible.toggle() }
    }
    private func run(_ action: @escaping @MainActor () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { await action() }
    }
    private func close() {
        guard !closing else { return }
        closing = true
        run {
            await model.flush()
            if let onClose { onClose() } else { dismiss() }
        }
    }
    private func queue(_ ids: [String]) {
        run {
            await model.download(ids)
            downloadsOpen = false
        }
    }
}
