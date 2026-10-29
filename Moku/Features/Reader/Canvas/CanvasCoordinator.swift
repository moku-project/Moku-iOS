import SwiftUI
import UIKit

@MainActor
final class CanvasCoordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var parent: ReaderCanvas
    weak var scroll: CanvasScrollView?
    let canvas = UIView()
    var views: [Int: UIImageView] = [:]
    var labels: [Int: UILabel] = [:]
    var skeletons: [Int: ReaderPageSkeleton] = [:]
    var ratios: [Int: CGFloat] = [:]
    var cache: [Int: UIImage] = [:]
    var work: [Int: Task<Void, Never>] = [:]
    var failed = Set<Int>()
    var paths: [String] = []
    var pageNumbers: [Int] = []
    var frames: [Int: CGRect] = [:]
    var lastSettings: MangaReadingSettings?
    var lastLandscape = false
    var reportedPage: Int?
    private var scrolledWindow: ClosedRange<Int>?
    var lastJump: UUID?
    var lastSize = CGSize.zero
    var layingOut = false
    var displayLink: CADisplayLink?
    var autoPaused = false
    var endAdvanced = false
    var lastScrollEnabled = false
    var lastContrast = false
    init(_ parent: ReaderCanvas) { self.parent = parent }
    func attach(_ scroll: CanvasScrollView) {
        self.scroll = scroll
        scroll.delegate = self
        scroll.backgroundColor = .black
        scroll.contentInsetAdjustmentBehavior = .never
        // Page turns are driven by gestures; rubber-banding would shift the page.
        scroll.bounces = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.addSubview(canvas)
        scroll.didLayout = { [weak self] in
            guard let self, let scroll = self.scroll, scroll.bounds.size != self.lastSize else {
                return
            }
            self.lastSize = scroll.bounds.size
            self.layout(anchor: nil)
        }
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        double.numberOfTapsRequired = 2
        let single = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        single.require(toFail: double)
        scroll.addGestureRecognizer(double)
        scroll.addGestureRecognizer(single)
        for direction in [UISwipeGestureRecognizer.Direction.left, .right] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipe(_:)))
            swipe.direction = direction
            swipe.numberOfTouchesRequired = 1
            swipe.delegate = self
            scroll.addGestureRecognizer(swipe)
            scroll.panGestureRecognizer.require(toFail: swipe)
        }
    }
    func update(_ value: ReaderCanvas) {
        parent = value
        guard let scroll else { return }
        let model = parent.model
        let numbers = model.isStrip ? model.pages.indices.map { $0 + 1 } : model.visiblePages
        let changed =
            paths != model.pages || numbers != pageNumbers
            || lastContrast != model.settings.optimizeContrast
        if paths != model.pages || lastContrast != model.settings.optimizeContrast {
            cache.removeAll()
        }
        lastContrast = model.settings.optimizeContrast
        let settings = model.settings
        let layoutChanged = lastSettings != settings || lastLandscape != model.landscape
        if changed {
            let animate =
                !paths.isEmpty && paths == model.pages && !model.isStrip && !parent.reduceMotion
            for task in work.values { task.cancel() }
            work.removeAll()
            for view in views.values { view.removeFromSuperview() }
            views.removeAll()
            labels.removeAll()
            skeletons.removeAll()
            failed.removeAll()
            if paths != model.pages {
                ratios.removeAll()
                endAdvanced = false
                autoPaused = false
            }
            paths = model.pages
            pageNumbers = numbers
            frames.removeAll(keepingCapacity: true)
            reportedPage = nil
            layout(anchor: model.page)
            if animate {
                switch settings.transition {
                case "fade":
                    canvas.alpha = 0
                    UIView.animate(withDuration: 0.18) { self.canvas.alpha = 1 }
                case "slide":
                    canvas.transform = CGAffineTransform(
                        translationX: settings.readingDirection == "rtl" ? -32 : 32, y: 0)
                    UIView.animate(withDuration: 0.18) { self.canvas.transform = .identity }
                case "flip":
                    UIView.transition(
                        with: canvas, duration: 0.25, options: .transitionCurlUp,
                        animations: nil)
                default: break
                }
            }
        }
        if layoutChanged {
            lastSettings = settings
            lastLandscape = model.landscape
            if !changed { layout(anchor: model.page) }
        }
        scroll.maximumZoomScale = model.behaviour.pinchZoom ? 3 : 1
        scroll.minimumZoomScale = 1
        if !model.behaviour.pinchZoom && scroll.zoomScale != 1 {
            scroll.setZoomScale(1, animated: false)
        }
        if lastJump != model.jumpID {
            lastJump = model.jumpID
            jump(model.page)
            autoPaused = false
        }
        let auto = model.behaviour.autoScroll && model.isStrip && parent.active
        if auto && !lastScrollEnabled { autoPaused = false }
        lastScrollEnabled = auto
        if auto && displayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !auto {
            displayLink?.invalidate()
            displayLink = nil
        }
        loadWindow()
    }
    func layout(anchor: Int?) {
        scrolledWindow = nil
        guard !layingOut, let scroll, scroll.bounds.width > 0 else { return }
        layingOut = true
        defer { layingOut = false }
        let visiblePage = parent.model.page
        let oldFrame = frames[visiblePage] ?? .zero
        let oldFraction =
            oldFrame.height > 0 ? (scroll.contentOffset.y - oldFrame.minY) / oldFrame.height : 0
        let viewport = scroll.bounds.size
        let model = parent.model
        let settings = model.settings
        let zoom = CGFloat(settings.readerZoom)
        let ordered =
            model.isStrip || settings.readingDirection != "rtl"
            ? pageNumbers : pageNumbers.reversed()
        var cursor: CGFloat = 0
        if model.isDouble, pageNumbers.count == 1, let page = pageNumbers.first {
            let onRight = settings.readingDirection == "rtl" ? page % 2 == 0 : page % 2 == 1
            if onRight { cursor = viewport.width / 2 }
        }
        var maxHeight: CGFloat = viewport.height
        for page in ordered {
            let ratio = ratios[page] ?? 0.7
            let available = viewport.width / CGFloat(model.isDouble ? 2 : 1)
            var width: CGFloat
            switch settings.fitMode {
            case "height": width = viewport.height * ratio
            case "screen": width = min(available, viewport.height * ratio)
            case "original":
                width =
                    cache[page].map {
                        $0.size.width / scroll.traitCollection.displayScale
                    } ?? available
            default: width = available
            }
            width = max(1, width * zoom)
            let height = width / ratio
            let x =
                model.isStrip
                ? max(0, (viewport.width - width) / 2)
                : cursor + max(0, (available - width) / 2)
            let y = model.isStrip ? cursor : max(0, (viewport.height - height) / 2)
            frames[page] = CGRect(x: x, y: y, width: width, height: height)
            views[page]?.frame = frames[page] ?? .zero
            skeletons[page]?.frame = CGRect(x: 0, y: 0, width: width, height: height)
            labels[page]?.frame = CGRect(x: 0, y: 0, width: width, height: min(height, 200))
            if model.isStrip {
                cursor += height + (settings.pageGap ? 8 : 0)
            } else {
                cursor += max(available, width)
                maxHeight = max(maxHeight, height)
            }
        }
        canvas.frame.size = CGSize(
            width: model.isStrip
                ? max(viewport.width, frames.values.map(\.maxX).max() ?? 0)
                : max(viewport.width, cursor),
            height: model.isStrip ? max(viewport.height, cursor) : maxHeight)
        scroll.contentSize = canvas.frame.size
        if let anchor {
            jump(anchor)
        } else if parent.model.isStrip, let frame = frames[visiblePage] {
            scroll.contentOffset.y = max(
                0,
                min(
                    frame.minY + oldFraction * frame.height,
                    canvas.bounds.height - scroll.bounds.height))
        }
        loadWindow()
    }
    func jump(_ page: Int) {
        guard let scroll else { return }
        let y = parent.model.isStrip ? frames[page]?.minY ?? 0 : 0
        scroll.setContentOffset(
            CGPoint(x: 0, y: max(0, min(y, scroll.contentSize.height - scroll.bounds.height))),
            animated: false)
    }
    func loadWindow() {
        guard let scroll, !paths.isEmpty else { return }
        let rect = scroll.convert(scroll.bounds, to: canvas)
        let visible: [Int]
        if parent.model.isStrip {
            let start = firstPageIndex(below: rect.minY)
            visible = Array(pageNumbers.dropFirst(start).prefix { (frames[$0]?.minY ?? .infinity) < rect.maxY })
        } else {
            visible = pageNumbers.filter { frames[$0]?.intersects(rect) == true }
        }
        guard let first = visible.min(), let last = visible.max() else { return }
        let ahead = max(0, min(12, parent.model.behaviour.preloadPages))
        let keep = Set(max(1, first - 1)...min(paths.count, last + ahead))
        cache = cache.filter { keep.contains($0.key) }
        for page in Array(work.keys) where !keep.contains(page) {
            work.removeValue(forKey: page)?.cancel()
        }
        // Keep UIKit views bounded too. Long chapters previously allocated an
        // image view, animated skeleton and label for every page before opening.
        let displayed = parent.model.isStrip ? keep : keep.intersection(pageNumbers)
        for page in Array(views.keys) where !displayed.contains(page) {
            skeletons.removeValue(forKey: page)?.setAnimating(false)
            labels.removeValue(forKey: page)
            views.removeValue(forKey: page)?.removeFromSuperview()
        }
        for page in displayed where views[page] == nil {
            let view = UIImageView(frame: frames[page] ?? .zero)
            view.contentMode = .scaleToFill
            view.image = cache[page]
            view.isAccessibilityElement = true
            view.accessibilityLabel = "Page \(page)"
            canvas.addSubview(view)
            views[page] = view
            let skeleton = ReaderPageSkeleton(frame: view.bounds)
            view.addSubview(skeleton)
            skeletons[page] = skeleton
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: min(view.bounds.height, 200)))
            label.textAlignment = .center
            label.textColor = .lightGray
            label.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
            label.text = failed.contains(page) ? "Page \(page) unavailable. Tap to retry." : nil
            label.isHidden = !failed.contains(page)
            view.addSubview(label)
            labels[page] = label
        }
        for (page, skeleton) in skeletons {
            let pending = cache[page] == nil && !failed.contains(page)
            skeleton.isHidden = !pending
            skeleton.setAnimating(pending && visible.contains(page) && parent.active && !parent.reduceMotion)
        }
        guard parent.active else {
            for task in work.values { task.cancel() }
            work.removeAll()
            return
        }
        // At most three transfers at once, including prefetch.
        for page in keep.sorted()
        where cache[page] == nil && work[page] == nil && !failed.contains(page) {
            guard work.count < 3, paths.indices.contains(page - 1) else { break }
            let bytes = cache.values.reduce(0) {
                $0 + (($1.cgImage?.bytesPerRow ?? 0) * ($1.cgImage?.height ?? 0))
            }
            if !visible.contains(page)
                && bytes + work.count * 16 * 1024 * 1024 >= 48 * 1024 * 1024
            {
                continue
            }
            let path = paths[page - 1]
            let model = parent.model
            work[page] = Task { [weak self] in
                do {
                    let data = try await model.image(path: path)
                    let image = try await PageDecoder.shared.decode(
                        data, contrast: self?.parent.model.settings.optimizeContrast ?? false)
                    try Task.checkCancellation()
                    guard let self, self.paths.indices.contains(page - 1),
                        self.paths[page - 1] == path
                    else { return }
                    self.work.removeValue(forKey: page)
                    self.cache[page] = image
                    self.views[page]?.image = image
                    self.labels[page]?.isHidden = true
                    self.labels[page]?.text = nil
                    self.skeletons[page]?.isHidden = true
                    let ratio = image.size.width / image.size.height
                    if self.ratios[page] != ratio {
                        self.ratios[page] = ratio
                        self.layout(anchor: nil)
                    }
                    self.loadWindow()
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.work.removeValue(forKey: page)
                    self.failed.insert(page)
                    self.labels[page]?.isHidden = false
                    self.labels[page]?.text = "Page \(page) unavailable. Tap to retry."
                    self.loadWindow()
                }
            }
        }
    }
    private func firstPageIndex(below y: CGFloat) -> Int {
        var lower = 0, upper = pageNumbers.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if (frames[pageNumbers[middle]]?.maxY ?? 0) <= y { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard !layingOut, parent.model.isStrip else { return }
        let visibleRect = scrollView.convert(scrollView.bounds, to: canvas)
        let y = visibleRect.minY + min(100, visibleRect.height / 3)
        let index = firstPageIndex(below: y)
        if pageNumbers.indices.contains(index) {
            let page = pageNumbers[index]
            let model = parent.model
            if page != reportedPage {
                reportedPage = page
                let chapterID = model.chapterID
                // Delegate callbacks can occur during SwiftUI updates.
                Task { @MainActor [weak self, weak model] in
                    guard self?.reportedPage == page, model?.chapterID == chapterID else { return }
                    model?.visiblePageChanged(page)
                }
            }
        }
        // loadWindow walks the cache and every page view; only rerun it when the
        // visible range moves to another page, not on every scrolled frame.
        let first = firstPageIndex(below: visibleRect.minY)
        let window = first...max(first, firstPageIndex(below: visibleRect.maxY))
        guard window != scrolledWindow else { return }
        scrolledWindow = window
        loadWindow()
    }
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) { autoPaused = true }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        reachedEnd()
    }
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { reachedEnd() }
    func reachedEnd() {
        guard let scroll, parent.model.isStrip, parent.model.behaviour.autoNextChapter,
            parent.active, !endAdvanced, scroll.contentSize.height > scroll.bounds.height,
            scroll.contentOffset.y >= scroll.contentSize.height - scroll.bounds.height - 2
        else { return }
        endAdvanced = true
        parent.model.visiblePageChanged(paths.count)
        parent.model.changeChapter(forward: true)
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UISwipeGestureRecognizer {
            return !parent.model.isStrip && scroll?.zoomScale == 1
        }
        return true
    }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { canvas }
    @objc func tap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: canvas)
        if let page = failed.first(where: { views[$0]?.frame.contains(point) == true }) {
            failed.remove(page)
            labels[page]?.text = nil
            labels[page]?.isHidden = true
            loadWindow()
            return
        }
        if !parent.model.behaviour.tapToToggleBar { parent.toggleChrome() }
    }
    @objc func doubleTap(_ gesture: UITapGestureRecognizer) { parent.toggleChrome() }
    @objc func swipe(_ gesture: UISwipeGestureRecognizer) {
        guard !parent.model.isStrip, scroll?.zoomScale == 1 else { return }
        let forward =
            (gesture.direction == .left) != (parent.model.settings.readingDirection == "rtl")
        parent.model.navigate(forward: forward)
    }
    @objc func tick(_ link: CADisplayLink) {
        guard !autoPaused, let scroll, !scroll.isDragging, !scroll.isDecelerating else {
            return
        }
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        scroll.contentOffset.y = min(
            maxY, scroll.contentOffset.y + parent.model.behaviour.autoScrollSpeed * 5 * min(0.1, link.targetTimestamp - link.timestamp))
        reachedEnd()
    }
    func stop() {
        for skeleton in skeletons.values { skeleton.setAnimating(false) }
        displayLink?.invalidate()
        displayLink = nil
        for task in work.values { task.cancel() }
        work.removeAll()
        scroll?.didLayout = nil
        scroll?.delegate = nil
    }
}
