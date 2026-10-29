import AVFoundation
import Observation

@MainActor @Observable
final class PlayerViewModel {
    let player = AVPlayer()
    let title: String
    let mediaID: String
    let chapters: [Chapter]
    let repository: any PlayerRepository
    private(set) var activityEntry: HomeEntry
    @ObservationIgnored private var activityPrepared = false
    var chapterID: String
    var stream: EpisodeStream?
    var sourceIndex: Int?
    var position = 0.0
    var duration = 0.0
    var speed: Float = 1
    var playing = false
    var isActive = true
    var autoplay = true
    var autoplayNext = true
    var autoSubtitles = true
    var subtitleLanguage = ""
    private(set) var episodeFinished = false
    var loading = false
    var buffering = false
    var error: String?
    var notice: String?
    var muted = false
    var subtitleIndex: Int?
    var cues: [SubtitleCue] = []
    var subtitleScale = 1.0
    var subtitleHeight = 9.0
    var subtitleBackground = false
    private var generation = UUID()
    private var subtitleGeneration = UUID()
    @ObservationIgnored private var automaticSubtitleTask: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private var finished = false
    private var loadedChapterID: String?
    var activityReady: Bool {
        loadedChapterID == chapterID && !loading && error == nil && duration > 0
    }
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    private var progressGeneration = UUID()
    private var resumePosition = 0.0
    private var seekGeneration = UUID()
    private var seeking = false

    init(
        title: String, mediaID: String, chapters: [Chapter], chapterID: String,
        repository: any PlayerRepository = LivePlayerRepository()
    ) {
        self.title = title
        self.activityEntry = HomeEntry(id: mediaID, title: title, media: "Anime")
        self.mediaID = mediaID
        self.chapters = chapters.sorted { ($0.number ?? 0) < ($1.number ?? 0) }
        self.chapterID = chapterID
        self.repository = repository
    }

    var index: Int { chapters.firstIndex { $0.id == chapterID } ?? 0 }
    var episodeLabel: String {
        guard chapters.indices.contains(index) else { return "Episode" }
        return "Ep. \(chapters[index].number?.formatted() ?? String(index + 1))"
    }
    var caption: String {
        cues.filter { $0.start <= position && position < $0.end }.map(\.text).joined(
            separator: "\n")
    }

    func load(minimumLoadingDuration: Duration = .zero) async {
        let revealAt = ContinuousClock.now.advanced(by: minimumLoadingDuration)
        let requestedChapterID = chapterID
        loadedChapterID = nil
        let token = UUID()
        generation = token
        cancelSeek()
        loading = true
        error = nil
        playing = false
        finished = false
        episodeFinished = false
        position = 0
        duration = 0
        stream = nil
        sourceIndex = nil
        subtitleIndex = nil
        automaticSubtitleTask?.cancel()
        automaticSubtitleTask = nil
        subtitleGeneration = UUID()
        cues = []
        player.pause()
        player.replaceCurrentItem(with: nil)
        do {
            if !activityPrepared {
                let chapters = chapters, mediaID = mediaID, title = title
                let prepared = await Task.detached(priority: .userInitiated) {
                    HomeEntry(id: mediaID, title: title, media: "Anime",
                              chapters: chapters.map { HomeChapter(id: $0.id, title: $0.label) })
                }.value
                try Task.checkCancellation()
                guard generation == token else { return }
                activityEntry = prepared
                activityPrepared = true
            }
            let (stream, resume) = try await repository.stream(chapterID: chapterID)
            try Task.checkCancellation()
            guard generation == token else { return }
            try await Task.sleep(until: revealAt, clock: .continuous)
            guard generation == token else { return }
            self.stream = stream
            if autoSubtitles, !stream.subtitles.isEmpty {
                let language = subtitleLanguage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let index = stream.subtitles.firstIndex { $0.lang.lowercased() == language || (!language.isEmpty && $0.lang.lowercased().hasPrefix(language + "-")) } ?? 0
                automaticSubtitleTask = Task { [weak self] in
                    guard let self, self.generation == token, !Task.isCancelled else { return }
                    await self.selectSubtitle(index)
                }
            }
            try await replace(path: stream.url, resume: resume, token: token, shouldPlay: autoplay)
            if generation == token { loadedChapterID = requestedChapterID }
        } catch is CancellationError {
        } catch {
            guard generation == token else { return }
            self.error = "Couldn’t open this episode. Try again or choose another source."
        }
        if generation == token { loading = false }
    }

    private func replace(path: String, resume: Double, token: UUID, shouldPlay: Bool) async throws {
        let request = try await repository.request(path: path)
        try Task.checkCancellation()
        guard generation == token, let url = request.url else { return }
        // All remote URLs come from Connection.contentRequest: authenticated loopback content only.
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]
            ])
        cancelSeek()
        player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        resumePosition = resume.isFinite ? max(0, resume) : 0
        finished = false
        playing = isActive && shouldPlay
        // Normal playback preserves AVPlayer's automatic stall
        // avoidance. playImmediately bypasses that policy on slow streams.
        if playing {
            player.defaultRate = speed
            player.play()
        }
    }

    func changeSource(_ index: Int) async {
        guard let stream, stream.sources.indices.contains(index) else { return }
        let token = UUID()
        generation = token
        let resume = position
        let shouldPlay = playing
        loading = true
        error = nil
        do {
            try await replace(
                path: stream.sources[index].url, resume: resume, token: token,
                shouldPlay: shouldPlay)
            if generation == token { sourceIndex = index }
        } catch {
            if generation == token {
                self.error = "Couldn’t play this source. Choose another source."
            }
        }
        if generation == token { loading = false }
    }

    func selectSubtitle(_ index: Int?) async {
        let token = UUID()
        subtitleGeneration = token
        subtitleIndex = index
        cues = []
        notice = nil
        guard let index, let stream, stream.subtitles.indices.contains(index) else { return }
        do {
            let text = try await repository.subtitle(path: stream.subtitles[index].url)
            guard !Task.isCancelled, subtitleGeneration == token else { return }
            let parsed = await Task.detached(priority: .userInitiated) { SubtitleCue.parse(text) }.value
            guard !Task.isCancelled, subtitleGeneration == token else { return }
            guard !parsed.isEmpty else {
                notice = "This subtitle format isn’t supported yet. Try another track."
                subtitleIndex = nil
                return
            }
            cues = parsed
        } catch {
            guard subtitleGeneration == token else { return }
            subtitleIndex = nil
            notice = "Couldn’t load subtitles. Try again."
        }
    }

    func togglePlayback() {
        if playing {
            player.pause()
            playing = false
        } else {
            if finished {
                seek(0)
                finished = false
            }
            playing = true
            player.defaultRate = speed
            player.play()
        }
    }

    func setSpeed(_ value: Float) {
        speed = value
        player.defaultRate = value
        if playing { player.rate = value }
    }

    func toggleMute() {
        muted.toggle()
        player.isMuted = muted
    }

    func seek(_ seconds: Double) {
        guard duration.isFinite, duration > 0, seconds.isFinite else { return }
        position = min(duration, max(0, seconds))
        resumePosition = 0
        finished = false
        episodeFinished = false
        let token = UUID()
        seekGeneration = token
        seeking = true
        // Keep the requested thumb position until this seek completes; a superseded
        // completion must not release a newer seek or move the timeline backwards.
        player.seek(
            to: CMTime(seconds: position, preferredTimescale: 600),
            toleranceBefore: .zero, toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.seekGeneration == token else { return }
                self.seeking = false
            }
        }
    }

    private func cancelSeek() {
        seekGeneration = UUID()
        seeking = false
        resumePosition = 0
        player.currentItem?.cancelPendingSeeks()
    }

    func tick() async {
        guard let item = player.currentItem else { return }
        if item.status == .failed {
            error = "This video couldn’t be played. Try another source or retry."
            playing = false
            buffering = false
            return
        }
        let total = item.duration.seconds
        if total.isFinite, total > 0 { duration = total }
        if resumePosition > 0, item.status == .readyToPlay, duration > 0 {
            seek(resumePosition < duration - 2 ? resumePosition : 0)
            resumePosition = 0
        } else if !seeking {
            let current = player.currentTime().seconds
            if current.isFinite { position = current }
        }
        buffering = playing && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        if !seeking, duration > 0, position >= duration - 0.25, !finished {
            finished = true
            episodeFinished = true
            playing = false
            saveSnapshot()
        } else if playing, progressTask == nil, Date().timeIntervalSince(lastSave) >= 10 {
            saveSnapshot()
        }
    }

    func saveSnapshot() {
        let repository = repository
        let mediaID = mediaID
        let chapterID = chapterID
        let position = position
        let duration = duration
        guard duration > 0 else { return }
        let previous = progressTask
        let token = UUID()
        progressGeneration = token
        lastSave = Date()
        progressTask = Task {
            await previous?.value
            do {
                try await repository.save(
                    mediaID: mediaID, chapterID: chapterID,
                    position: position, duration: duration)
            } catch {
                if self.chapterID == chapterID { notice = "Playback progress couldn’t be saved." }
            }
            if progressGeneration == token { progressTask = nil }
        }
    }

    func stop() {
        generation = UUID()
        subtitleGeneration = UUID()
        automaticSubtitleTask?.cancel()
        automaticSubtitleTask = nil
        cancelSeek()
        player.pause()
        playing = false
        loading = false
        buffering = false
    }

    static func time(_ value: Double) -> String {
        let seconds = value.isFinite ? Int(min(Double(Int32.max), max(0, value))) : 0
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
