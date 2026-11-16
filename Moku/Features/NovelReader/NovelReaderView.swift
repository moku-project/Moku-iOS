import SwiftUI

/// Chapters read on one after another or one at a time, with paging, typography, paper themes and synced progress.
struct NovelReaderView: View {
    @State var model: NovelReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("novel.theme") private var theme: NovelTheme = .dark
    @AppStorage("novel.font") private var font: NovelFont = .serif
    @AppStorage("novel.size") private var size = 1.1
    @AppStorage("novel.lineHeight") private var lineHeight = 1.7
    @AppStorage("novel.paragraphGap") private var paragraphGap = 0.9
    @AppStorage("novel.width") private var width = 70.0
    @AppStorage("novel.paged") private var paged = false
    @AppStorage("novel.continuous") private var continuous = true
    @AppStorage("novel.justified") private var justified = false
    @AppStorage("novel.autoScrollSpeed.v2") private var autoScrollSpeed = 5.0
    @AppStorage("novel.guide") private var guide = false
    @AppStorage("novel.guideLines") private var guideLines = 3
    @State private var autoScrollPausedUntil = ContinuousClock.now
    @AppStorage("novel.bookmarks") private var bookmarkData = Data()
    @State private var autoScrolling = false

    @State private var chromeVisible = true
    @State private var settingsOpen = false
    @State private var chaptersOpen = false
    @State private var position = ScrollPosition(edge: .top)
    @State private var geometry = ScrollMetrics()
    @State private var previousIdleTimer = false
    @State private var sectionFrames: [String: CGRect] = [:]

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var content: CGFloat = 0
        var viewport: CGFloat = 0
        var width: CGFloat = 0
        var fraction: Double {
            let range = content - viewport
            return range > 1 ? Double(offset / range) : (content > 0 ? 1 : 0)
        }
    }

    private var bodySize: CGFloat { 17 * size }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            content
            if guide && model.ready { readingGuide.allowsHitTesting(false) }
            if chromeVisible { chrome.transition(.opacity) }
        }
        .foregroundStyle(theme.text)
        .tint(NavigationStyle.accent)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .statusBarHidden(!chromeVisible)
        .persistentSystemOverlays(chromeVisible ? .visible : .hidden)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: chromeVisible)
        .preference(key: GeneralMediaPresentedKey.self, value: true)
        .task(id: model.loadID) { await model.load() }
        .task(id: autoScrolling) { await runAutoScroll() }
        .onChange(of: continuous) { _, _ in
            if model.sections.count > 1, let chapter = model.chapter { model.open(chapter) }
        }
        .onChange(of: model.loadID) { _, _ in
            autoScrolling = false
            sectionFrames = [:]
        }
        .onChange(of: model.resumeAt) { _, resume in
            // Bookmark jumps inside the open chapter: layout is already known.
            guard let resume, geometry.content > geometry.viewport else { return }
            model.didResume()
            position.scrollTo(y: max(0, CGFloat(resume) * (geometry.content - geometry.viewport)))
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { model.flush() } }
        .onAppear {
            // Keep the screen on while reading.
            previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.flush()
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
        }
        .recordActivity(
            mediaID: model.details.id, chapterID: model.chapterID,
            position: Int(model.progress * 100),
            active: !settingsOpen && !chaptersOpen, valid: model.ready
        )
        .sheet(isPresented: $settingsOpen) { settings }
        .sheet(isPresented: $chaptersOpen) { chapterList }
        .accessibilityIdentifier("novel.reader")
    }

    @ViewBuilder private var content: some View {
        if model.ready {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(continuous ? model.sections : Array(model.sections.prefix(1))) {
                        section in
                        sectionView(section)
                            .onGeometryChange(for: CGRect.self) {
                                $0.frame(in: .scrollView)
                            } action: {
                                sectionFrames[section.id] = $0
                            }
                    }
                    footer
                }
                .frame(maxWidth: width * bodySize * 0.55, alignment: .leading)
                .padding(.horizontal, 22)
                .padding(.top, 72)
                .padding(.bottom, 120)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition($position)
            .scrollIndicators(paged ? .hidden : .automatic)
            .onScrollGeometryChange(for: ScrollMetrics.self) { scroll in
                ScrollMetrics(
                    offset: scroll.contentOffset.y + scroll.contentInsets.top,
                    content: scroll.contentSize.height, viewport: scroll.containerSize.height,
                    width: scroll.containerSize.width)
            } action: { _, metrics in
                geometry = metrics
                if let resume = model.resumeAt, metrics.content > metrics.viewport {
                    model.didResume()
                    position.scrollTo(
                        y: max(0, CGFloat(resume) * (metrics.content - metrics.viewport)))
                } else if model.resumeAt == nil {
                    trackChapter(metrics)
                }
            }
            .onScrollPhaseChange { _, phase in
                // Touching the text pauses auto scroll for a moment.
                if phase == .interacting || phase == .tracking {
                    autoScrollPausedUntil = .now + .seconds(2.5)
                }
            }
            // On the scroll view itself, so taps never steal the scroll pan.
            .onTapGesture { location in tap(at: location.x) }
            .id(model.loadID)
        } else if let error = model.error {
            VStack(spacing: 14) {
                Text(error).multilineTextAlignment(.center).foregroundStyle(theme.secondary)
                Button("Try again") { Task { await model.load() } }.frame(minHeight: 44)
                Button("Close") { dismiss() }.frame(minHeight: 44)
            }
            .padding(32)
            .accessibilityIdentifier("novel.error")
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(0..<9, id: \.self) { line in
                    RoundedRectangle(cornerRadius: 4).fill(theme.secondary.opacity(0.15))
                        .frame(height: 14).frame(maxWidth: line % 3 == 2 ? 220 : .infinity)
                }
            }
            .padding(28).padding(.top, 60)
            .frame(maxHeight: .infinity, alignment: .top)
            .accessibilityLabel("Loading chapter")
        }
    }

    @ViewBuilder private func blockView(_ block: NovelDocument.Block) -> some View {
        switch block {
        case .paragraph(let text):
            if justified {
                NovelParagraph(
                    text: text, font: font, size: bodySize,
                    lineSpacing: bodySize * (lineHeight - 1), color: theme.text
                )
                .padding(.bottom, bodySize * paragraphGap)
            } else {
                Text(text)
                    .font(fontFor(size: bodySize))
                    .lineSpacing(bodySize * (lineHeight - 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, bodySize * paragraphGap)
                    .textSelection(.enabled)
            }
        case .heading(let text):
            Text(text)
                .font(fontFor(size: bodySize * 1.2, weight: .semibold))
                .padding(.top, bodySize * 0.6).padding(.bottom, bodySize * paragraphGap)
                .accessibilityAddTraits(.isHeader)
        case .rule:
            Rectangle().fill(theme.secondary.opacity(0.35)).frame(width: 80, height: 1)
                .frame(maxWidth: .infinity).padding(.vertical, bodySize)
        }
    }

    private func sectionView(_ section: NovelReaderViewModel.Section) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(section.chapter.label)
                .font(fontFor(size: bodySize * 1.35, weight: .semibold))
                .padding(.bottom, bodySize * 1.4)
                .padding(.top, section.id == model.sections.first?.id ? 0 : bodySize * 3)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(section.document.blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    /// Progress follows the chapter at the top of the screen; nearing the end loads the next one.
    private func trackChapter(_ metrics: ScrollMetrics) {
        guard continuous, model.sections.count > 1 || model.upcoming != nil else {
            return model.scrolled(to: metrics.fraction)
        }
        let line = metrics.viewport * 0.25
        if let current = model.sections.last(where: {
            (sectionFrames[$0.id]?.minY ?? .infinity) <= line
        })
            ?? model.sections.first, let frame = sectionFrames[current.id]
        {
            let range = frame.height - metrics.viewport
            let fraction =
                range > 1 ? Double(-frame.minY / range) : (frame.maxY <= metrics.viewport ? 1 : 0)
            model.enter(current.id, at: fraction)
        }
        if metrics.content - metrics.offset - metrics.viewport < metrics.viewport * 2 {
            Task { await model.appendNext() }
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(theme.secondary.opacity(0.25)).frame(height: 1).padding(.vertical, 24)
            if continuous, model.upcoming != nil {
                ProgressView().frame(maxWidth: .infinity, minHeight: 56)
                    .accessibilityLabel("Loading the next chapter")
            } else if !continuous, let next = model.next {
                Button {
                    model.advance()
                } label: {
                    VStack(spacing: 4) {
                        Text("Next chapter").font(.subheadline.weight(.semibold))
                        Text(next.label).font(.caption).foregroundStyle(theme.secondary).lineLimit(
                            1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(
                        theme.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("novel.next")
            } else {
                Text("You’re all caught up.").font(.subheadline).foregroundStyle(theme.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Edge thirds turn pages in paged mode; everything else toggles the bars.
    private func tap(at x: CGFloat) {
        let zone = geometry.width > 0 ? x / geometry.width : 0.5
        if paged && zone < 0.3 {
            turn(-1)
        } else if paged && zone > 0.7 {
            turn(1)
        } else {
            toggleChrome()
        }
    }

    private func toggleChrome() { chromeVisible.toggle() }

    private var bookmark: NovelBookmark? { NovelBookmark.all(bookmarkData)[model.details.id] }
    private var bookmarkedHere: Bool {
        guard let bookmark, bookmark.chapterID == model.chapterID else { return false }
        return abs(bookmark.fraction - model.progress) < 0.02
    }

    private func toggleBookmark() {
        var all = NovelBookmark.all(bookmarkData)
        if bookmarkedHere {
            all.removeValue(forKey: model.details.id)
            Toaster.shared.show("Saved place removed", kind: .info)
        } else {
            all[model.details.id] = NovelBookmark(
                chapterID: model.chapterID, fraction: model.progress)
            Toaster.shared.show(
                "Place saved",
                detail: "\(model.chapter?.label ?? "This chapter") · \(Int(model.progress * 100))%")
        }
        bookmarkData = NovelBookmark.encode(all)
    }

    /// A tinted band of one to eight lines across the middle of the screen, to keep your place.
    private var readingGuide: some View {
        let height = bodySize * lineHeight * CGFloat(guideLines) + 4
        return Rectangle()
            .fill(theme.text.opacity(0.08))
            .overlay(alignment: .top) {
                Rectangle().fill(theme.text.opacity(0.22)).frame(height: 1)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(theme.text.opacity(0.22)).frame(height: 1)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .ignoresSafeArea()
            .accessibilityHidden(true)
    }

    /// Glides at speed 1 (slow) to 30 (fast); pauses when the bars show and stops at the chapter end.
    private func runAutoScroll() async {
        guard autoScrolling else { return }
        chromeVisible = false
        let clock = ContinuousClock()
        var last = clock.now
        while autoScrolling, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            let now = clock.now
            let elapsed = (now - last) / .seconds(1)
            last = now
            let end = max(0, geometry.content - geometry.viewport)
            guard geometry.offset < end - 1 else {
                autoScrolling = false
                break
            }
            if chromeVisible || settingsOpen || chaptersOpen || now < autoScrollPausedUntil {
                continue
            }
            position.scrollTo(
                y: min(end, geometry.offset + CGFloat(autoScrollSpeed * 30 * elapsed)))
        }
    }

    /// Paged mode turns by a screen minus two lines, so no line is skipped.
    private func turn(_ direction: CGFloat) {
        let step = max(100, geometry.viewport - bodySize * lineHeight * 2)
        let target = min(
            max(0, geometry.offset + direction * step), max(0, geometry.content - geometry.viewport)
        )
        if direction > 0, !continuous, geometry.offset >= geometry.content - geometry.viewport - 2,
            model.next != nil
        {
            model.advance()
            return
        }
        if reduceMotion {
            position.scrollTo(y: target)
        } else {
            withAnimation(.easeOut(duration: 0.25)) { position.scrollTo(y: target) }
        }
        if chromeVisible { chromeVisible = false }
    }

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                barButton("xmark", label: "Close") { dismiss() }
                Button {
                    chaptersOpen = true
                } label: {
                    VStack(spacing: 1) {
                        Text(model.details.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 3) {
                            Text(model.chapter?.label ?? "").lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                        }
                        .font(.caption).foregroundStyle(theme.secondary)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 44).frame(maxWidth: .infinity)
                    .glassSurface(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Choose a chapter")
                .accessibilityIdentifier("novel.chapters")
                barButton("textformat.size", label: "Reader Settings") { settingsOpen = true }
                    .accessibilityIdentifier("novel.settings")
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            Spacer()
            HStack(spacing: 4) {
                pageButton("chevron.backward", label: "Previous Chapter") {
                    if let previous = model.previous { model.open(previous) }
                }
                .disabled(model.previous == nil)
                ProgressView(value: model.progress).tint(NavigationStyle.accent)
                    .accessibilityLabel("Chapter progress")
                    .accessibilityValue("\(Int(model.progress * 100)) percent")
                Text("\(Int(model.progress * 100))%").font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondary).frame(width: 40)
                pageButton(
                    autoScrolling ? "pause.fill" : "play.fill",
                    label: autoScrolling ? "Pause Auto Scroll" : "Auto Scroll"
                ) {
                    autoScrolling.toggle()
                    if autoScrolling { chromeVisible = false }
                }
                .accessibilityIdentifier("novel.autoScroll")
                pageButton("chevron.forward", label: "Next Chapter") { model.advance() }
                    .disabled(model.next == nil)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .glassSurface(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .padding(.horizontal, 12).padding(.bottom, 4)
        }
        .foregroundStyle(theme.text)
    }

    private func barButton(_ symbol: String, label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 44, height: 44).glassSurface(Circle()).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func pageButton(_ symbol: String, label: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func fontFor(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch font {
        case .serif: .system(size: size, weight: weight, design: .serif)
        case .sans: .system(size: size, weight: weight)
        case .rounded: .system(size: size, weight: weight, design: .rounded)
        case .mono: .system(size: size, weight: weight, design: .monospaced)
        case .georgia, .palatino, .avenir:
            .custom(font.postScriptName, size: size).weight(weight)
        }
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Theme") {
                    Picker("Theme", selection: $theme) {
                        ForEach(NovelTheme.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Text") {
                    Picker("Font", selection: $font) {
                        ForEach(NovelFont.allCases) { Text($0.title).tag($0) }
                    }
                    stepper(
                        "Size", value: $size, range: 0.8...2.0, step: 0.05,
                        format: { "\(Int($0 * 100))%" })
                    stepper(
                        "Line height", value: $lineHeight, range: 1.3...2.4, step: 0.1,
                        format: { $0.formatted(.number.precision(.fractionLength(1))) })
                    stepper(
                        "Paragraph gap", value: $paragraphGap, range: 0.3...2.2, step: 0.1,
                        format: { $0.formatted(.number.precision(.fractionLength(1))) })
                    stepper(
                        "Column width", value: $width, range: 30...160, step: 5,
                        format: { "\(Int($0))" })
                }
                Section("Layout") {
                    Toggle("Justify text", isOn: $justified)
                    Toggle("Continuous chapters", isOn: $continuous)
                }
                Section("Behaviour") {
                    Toggle("Tap edges to turn pages", isOn: $paged)
                    stepper(
                        "Auto scroll speed", value: $autoScrollSpeed, range: 1...30, step: 1,
                        format: { "\(Int($0))" })
                }
                Section("Reading guide") {
                    Toggle("Guide bar", isOn: $guide)
                    if guide {
                        Stepper(value: $guideLines, in: 1...8) {
                            HStack {
                                Text("Thickness")
                                Spacer()
                                Text("\(guideLines) line\(guideLines == 1 ? "" : "s")")
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                    }
                }
                Section {
                    Text(
                        "The quick brown fox jumps over the lazy dog. Typography changes apply as you go."
                    )
                    .font(fontFor(size: bodySize))
                    .lineSpacing(bodySize * (lineHeight - 1))
                    .foregroundStyle(theme.text)
                    .listRowBackground(theme.background)
                } header: {
                    Text("Preview")
                }
            }
            .textCase(nil)
            .navigationTitle("Reader Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { settingsOpen = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func stepper(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double,
        format: @escaping (Double) -> String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value.wrappedValue)).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var chapterList: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        Button {
                            toggleBookmark()
                        } label: {
                            Label(
                                bookmarkedHere ? "Forget Saved Place" : "Save Place Here",
                                systemImage: bookmarkedHere ? "mappin.slash" : "mappin.and.ellipse")
                        }
                        .accessibilityIdentifier("novel.bookmark")
                        if let bookmark, !bookmarkedHere,
                            let marked = model.chapters.first(where: { $0.id == bookmark.chapterID }
                            )
                        {
                            Button {
                                model.open(bookmark)
                                chaptersOpen = false
                            } label: {
                                Label {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Go to Saved Place")
                                        Text("\(marked.label) · \(Int(bookmark.fraction * 100))%")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                } icon: {
                                    Image(systemName: "mappin.and.ellipse").foregroundStyle(
                                        NavigationStyle.accent)
                                }
                                .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("novel.gotoBookmark")
                        }
                    }
                    Section {
                        ForEach(model.chapters) { chapter in
                            Button {
                                model.open(chapter)
                                chaptersOpen = false
                            } label: {
                                HStack {
                                    Text(chapter.label).foregroundStyle(
                                        chapter.completed ? .secondary : .primary)
                                    Spacer()
                                    if chapter.id == model.chapterID {
                                        Image(systemName: "book.fill").foregroundStyle(
                                            NavigationStyle.accent)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                            .id(chapter.id)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(model.chapterID, anchor: .center) }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { chaptersOpen = false }
                }
            }
        }
    }
}

enum NovelTheme: String, CaseIterable, Identifiable {
    case paper, sepia, dark, black
    var id: Self { self }
    var title: String { rawValue.capitalized }
    var isDark: Bool { self == .dark || self == .black }
    var background: Color {
        switch self {
        case .paper: Color(red: 0.97, green: 0.95, blue: 0.92)
        case .sepia: Color(red: 0.95, green: 0.90, blue: 0.80)
        case .dark: Color(red: 0.09, green: 0.09, blue: 0.10)
        case .black: .black
        }
    }
    var text: Color {
        switch self {
        case .paper: Color(red: 0.13, green: 0.12, blue: 0.11)
        case .sepia: Color(red: 0.29, green: 0.23, blue: 0.16)
        case .dark: Color(red: 0.85, green: 0.84, blue: 0.81)
        case .black: Color(red: 0.78, green: 0.77, blue: 0.74)
        }
    }
    var secondary: Color { text.opacity(0.6) }
}

enum NovelFont: String, CaseIterable, Identifiable {
    case serif, sans, rounded, mono, georgia, palatino, avenir
    var id: Self { self }
    var title: String {
        switch self {
        case .serif: "New York"
        case .sans: "San Francisco"
        case .rounded: "Rounded"
        case .mono: "Monospace"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .avenir: "Avenir Next"
        }
    }
    var postScriptName: String {
        switch self {
        case .georgia: "Georgia"
        case .palatino: "Palatino-Roman"
        case .avenir: "AvenirNext-Regular"
        default: ""
        }
    }
}
