#if DEBUG
    import SwiftUI
    import UIKit

    /// Explicit launch-only fixture; production always uses LiveReaderRepository.
    enum ReaderPreview {
        @MainActor static func view() -> some View {
            let defaults = UserDefaults(suiteName: "com.moku.reader.preview")!
            if !ProcessInfo.processInfo.arguments.contains("--reader-keep-preferences") {
                defaults.removePersistentDomain(forName: "com.moku.reader.preview")
            }
            return ReaderView(
                details: details, chapterID: "11",
                preferences: ReaderPreferences(defaults: defaults),
                repository: PreviewReaderRepository())
        }
        static let details = MediaDetails(
            id: "reader-preview", title: "The Last Wayfarer", thumbnailUrl: nil, description: nil,
            author: nil, artist: nil, status: nil, genres: [], inLibrary: true,
            chapters: (10...14).map {
                Chapter(
                    id: String($0), title: "Chapter \($0)", number: Double($0),
                    scanlator: "Reader test fixture", completed: $0 < 11, downloaded: false)
            })
    }
    struct PreviewReaderRepository: ReaderRepository {
        /// `--ui-testing-reader-pdf`: pages are PDF pages, drawn by PDFPageSource
        /// from a generated three-page file, exactly as for a PDF-backed chapter.
        var pdf = ProcessInfo.processInfo.arguments.contains("--ui-testing-reader-pdf")
        func pages(chapterID: String) async throws -> [String] {
            if pdf { return (1...3).map { "/content/1/\(chapterID)/pdfpage/\($0)" } }
            return (1...12).map { "fixture/\(chapterID)/\($0)" }
        }
        func image(path: String) async throws -> Data {
            if PDFPageSource.parse(path) != nil {
                return try await PDFPageSource.shared.image(path: path) { _ in await Self.pdfFixture() }
            }
            try Task.checkCancellation()
            return await MainActor.run {
                let page = path.split(separator: "/").last.map(String.init) ?? "1"
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                return UIGraphicsImageRenderer(
                    size: CGSize(width: 720, height: 1080), format: format
                ).pngData { ctx in
                    UIColor(white: 0.92, alpha: 1).setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 720, height: 1080))
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.monospacedSystemFont(ofSize: 20, weight: .regular),
                        .foregroundColor: UIColor.darkGray,
                    ]
                    "THE LAST WAYFARER · PAGE \(page)".draw(
                        at: CGPoint(x: 32, y: 24), withAttributes: attributes)
                    for (index, frame) in [
                        CGRect(x: 24, y: 72, width: 672, height: 430),
                        CGRect(x: 24, y: 520, width: 324, height: 480),
                        CGRect(x: 366, y: 520, width: 330, height: 480),
                    ].enumerated() {
                        UIColor(white: CGFloat(index) * 0.06 + 0.15, alpha: 1).setFill()
                        ctx.fill(frame)
                        let p = UIBezierPath()
                        p.move(to: CGPoint(x: frame.minX, y: frame.maxY))
                        p.addLine(to: CGPoint(x: frame.midX, y: frame.minY + 100))
                        p.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
                        p.close()
                        UIColor(white: 0.46, alpha: 1).setFill()
                        p.fill()
                        UIColor(white: 0.76, alpha: 1).setFill()
                        UIBezierPath(
                            ovalIn: CGRect(
                                x: frame.midX - 25, y: frame.minY + 40, width: 50, height: 50)
                        ).fill()
                    }
                    "Deterministic reader fixture".draw(
                        at: CGPoint(x: 32, y: 1030), withAttributes: attributes)
                }
            }
        }
        @MainActor static func pdfFixture() -> Data {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .semibold), .foregroundColor: UIColor.darkGray,
            ]
            return UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 600, height: 840)).pdfData { context in
                for page in 1...3 {
                    // Page 2 is landscape, like a two-page spread in a scanned PDF.
                    let bounds = page == 2 ? CGRect(x: 0, y: 0, width: 840, height: 600) : CGRect(x: 0, y: 0, width: 600, height: 840)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    UIColor(white: 0.85, alpha: 1).setFill()
                    context.fill(bounds.insetBy(dx: 30, dy: 30))
                    "PDF page \(page)".draw(at: CGPoint(x: 60, y: 60), withAttributes: attributes)
                }
            }
        }
        func progress(mediaID: String, chapterID: String, value: Double, completed: Bool)
            async throws
        {}
        func download(mediaID: String, chapterIDs: [String]) async throws {}
    }
#endif
