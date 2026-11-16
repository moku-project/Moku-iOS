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
    @State private var filter = ""
    @State private var nextCount = 5
    @State private var actionTask: Task<Void, Never>?
    @State private var closing = false
    @State private var downloadsAfterSettings = false
    @State private var previousIdleTimer = false

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
                                && !downloadsOpen,
                            reduceMotion: !motion, toggleChrome: toggleChrome
                        )
                        .ignoresSafeArea()
                    }
                }
                .firstLoadSkeleton(
                    "reader-\(model.chapterID)", loading: model.loading, style: .reader)
                if model.chromeVisible {
                    VStack(spacing: 0) {
                        topBar
                        Spacer(minLength: 0)
                        bottomBar
                    }
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .transition(.opacity)
                }
                if let resumed = model.resumedPage, model.page == resumed, model.chromeVisible {
                    VStack {
                        Spacer()
                        Button {
                            model.resumedPage = nil
                        } label: {
                            Label("Resumed on page \(resumed)", systemImage: "book")
                                .font(.footnote.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 10)
                                .glassSurface(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Dismisses this notice")
                        .accessibilityIdentifier("reader.resumed")
                        .padding(.bottom, 96)
                    }
                    .transition(.opacity)
                    .task(id: resumed) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation(motion ? .easeOut(duration: 0.4) : nil) {
                            model.resumedPage = nil
                        }
                    }
                }
            }
            .onChange(of: geometry.size, initial: true) { _, size in
                model.landscape = size.width / max(1, size.height) > 1.25
            }
        }
        .focusable().focusEffectDisabled().focused($keyboardFocused)
        .onKeyPress(phases: [.down, .repeat]) { press in handleKey(press) }
        .onAppear {
            keyboardFocused = true
            // Keep the screen on while reading.
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
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
        .onDisappear {
            actionTask?.cancel()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
        }
        .recordActivity(
            mediaID: model.details.id, chapterID: model.chapterID, position: model.page,
            active: !model.drawerOpen && !pickerOpen && !downloadsOpen,
            valid: model.activityReady
        )
        .sheet(
            isPresented: Binding(get: { model.drawerOpen }, set: { model.drawerOpen = $0 }),
            onDismiss: {
                keyboardFocused = true
                if downloadsAfterSettings {
                    downloadsAfterSettings = false
                    downloadsOpen = true
                }
            }
        ) { settingsSheet }
        .sheet(isPresented: $pickerOpen) {
            ChapterPicker(model: model, filter: $filter, pickerOpen: $pickerOpen)
        }
        .sheet(isPresented: $downloadsOpen) {
            DownloadPicker(
                model: model, nextCount: $nextCount, downloadsOpen: $downloadsOpen, queue: queue)
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
        guard !model.loading, !pickerOpen, !downloadsOpen, !model.drawerOpen else {
            return .ignored
        }
        let values = ReaderShortcut.values(readerShortcuts)
        guard
            let action = ReaderShortcut.all.first(where: {
                ReaderShortcut.matches(values[$0.id] ?? $0.defaultValue, press: press)
            })
        else { return .ignored }
        if press.phase == .repeat && !["pageRight", "pageLeft"].contains(action.id) {
            return .handled
        }
        switch action.id {
        case "pageRight": keyboardPage(forward: model.settings.readingDirection != "rtl")
        case "pageLeft": keyboardPage(forward: model.settings.readingDirection == "rtl")
        case "firstPage": model.jump(1)
        case "lastPage": model.jump(model.pages.count)
        case "chapterRight": model.changeChapter(forward: true)
        case "chapterLeft": model.changeChapter(forward: false)
        case "exit": close()
        case "direction":
            model.settings.readingDirection =
                model.settings.readingDirection == "ltr" ? "rtl" : "ltr"
        case "layout":
            let layouts = ["single", "double", "auto", "longstrip"]
            model.settings.pageStyle =
                layouts[
                    ((layouts.firstIndex(of: model.settings.pageStyle) ?? 0) + 1) % layouts.count]
        case "fullscreen": toggleChrome()
        case "settings": drawer(true)
        case "scroll": model.preferences.document.behaviour.autoScroll.toggle()
        default: return .ignored
        }
        return .handled
    }
    private func keyboardPage(forward: Bool) {
        if model.settings.pageStyle == "longstrip" {
            model.jump(min(model.pages.count, max(1, model.page + (forward ? 1 : -1))))
        } else {
            model.navigate(forward: forward)
        }
    }
    private var topBar: some View {
        HStack(spacing: 10) {
            barButton("xmark", label: "Close", id: "reader.close", action: close)
            Button {
                pickerOpen = true
            } label: {
                VStack(spacing: 1) {
                    Text(model.details.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    HStack(spacing: 3) {
                        Text(model.chapter?.label ?? "Chapter").lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .glassSurface(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.details.title), \(model.chapter?.label ?? "Chapter")")
            .accessibilityHint("Choose a chapter")
            .accessibilityIdentifier("reader.chapters")
            barButton("textformat.size", label: "Reader Settings", id: "reader.settings") {
                drawer(true)
            }
        }
    }
    private var rtl: Bool { model.settings.readingDirection == "rtl" && !model.isStrip }
    private var bottomBar: some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                pageButton(
                    "chevron.backward", label: "Previous Page", id: "reader.previous", forward: rtl
                )
                .disabled(model.loading || (rtl ? !model.canNext : !model.canPrevious))
                Slider(
                    value: Binding(
                        get: { Double(model.page) }, set: { model.jump(Int($0.rounded())) }),
                    in: 1...Double(max(2, model.pages.count)), step: 1
                )
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .disabled(model.pages.count < 2)
                .accessibilityLabel("Page")
                .accessibilityValue("\(model.page) of \(model.pages.count)")
                .accessibilityIdentifier("reader.page")
                pageButton("chevron.forward", label: "Next Page", id: "reader.next", forward: !rtl)
                    .disabled(model.loading || (rtl ? !model.canPrevious : !model.canNext))
            }
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 8)
        .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
    private func pageButton(_ symbol: String, label: String, id: String, forward: Bool) -> some View
    {
        Button {
            model.navigate(forward: forward)
        } label: {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func barButton(
        _ symbol: String, label: String, id: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .foregroundStyle(Color(white: 0.92))
                .frame(width: 44, height: 44)
                .glassSurface(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private var settingsSheet: some View {
        NavigationStack {
            Form {
                ReaderSettingsView(
                    preferences: model.preferences, mediaID: model.details.id,
                    landscape: model.landscape)
                Section {
                    Button {
                        downloadsAfterSettings = true
                        model.drawerOpen = false
                    } label: {
                        Label("Download Chapters…", systemImage: "arrow.down.circle")
                    }
                    .accessibilityIdentifier("reader.downloads")
                }
            }
            .accessibilityIdentifier("reader.drawer.scroll")
            .tint(NavigationStyle.accent)
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { drawer(false) }.accessibilityIdentifier("reader.drawer.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    private func drawer(_ open: Bool) {
        model.drawerOpen = open
        model.chromeVisible = true
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
