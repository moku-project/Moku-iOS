import Foundation
import PDFKit
import UIKit

/// Desktop pdfRender counterpart. A PDF-backed chapter lists its pages as
/// `/content/{media}/{chapter}/pdfpage/{n}`: nothing is served at those paths.
/// The whole file comes once from `/content/{media}/{chapter}/pdf`, and each page
/// is drawn here, then handed to the reader as image data like any other page.
actor PDFPageSource {
    static let shared = PDFPageSource()
    /// Pages are drawn at most this wide; tall pages are capped by pixel count.
    private static let maxWidth: CGFloat = 1600
    private static let maxPixels: CGFloat = 8_000_000

    /// One chapter at a time, like desktop clearing its document cache on leave.
    private var document: (path: String, pdf: PDFDocument)?
    private var loading: (path: String, task: Task<Data, any Error>)?

    /// `(document path, page index)` for a pdfpage path, or nil for normal pages.
    nonisolated static func parse(_ path: String) -> (document: String, index: Int)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 5, parts[0] == "content", parts[3] == "pdfpage",
              let page = Int(parts[4]), page >= 1 else { return nil }
        return ("/content/\(parts[1])/\(parts[2])/pdf", page - 1)
    }

    func image(path: String, load: @Sendable @escaping (String) async throws -> Data) async throws -> Data {
        guard let (documentPath, index) = Self.parse(path) else {
            throw EmbeddedSearchError.message("Not a PDF page.")
        }
        let pdf = try await document(documentPath, load: load)
        guard let page = pdf.page(at: index) else {
            throw EmbeddedSearchError.message("This PDF has no page \(index + 1).")
        }
        try Task.checkCancellation()
        return try Self.render(page)
    }

    private func document(_ path: String, load: @Sendable @escaping (String) async throws -> Data) async throws -> PDFDocument {
        if let document, document.path == path { return document.pdf }
        // Pages ask in parallel; the file is fetched once and shared.
        let task: Task<Data, any Error>
        if let loading, loading.path == path {
            task = loading.task
        } else {
            task = Task { try await load(path) }
            loading = (path, task)
        }
        let data = try await task.value
        if loading?.path == path { loading = nil }
        if let document, document.path == path { return document.pdf }
        guard let pdf = PDFDocument(data: data), pdf.pageCount > 0 else {
            throw EmbeddedSearchError.message("This PDF couldn’t be read.")
        }
        document = (path, pdf)
        return pdf
    }

    private static func render(_ page: PDFPage) throws -> Data {
        var bounds = page.bounds(for: .cropBox).size
        // Rotated pages (90° or 270°) are wider than their crop box says.
        if page.rotation % 180 != 0 { bounds = CGSize(width: bounds.height, height: bounds.width) }
        guard bounds.width > 0, bounds.height > 0 else {
            throw EmbeddedSearchError.message("This PDF page is empty.")
        }
        let scale = min(maxWidth / bounds.width, sqrt(maxPixels / (bounds.width * bounds.height)))
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        // thumbnail(of:for:) draws on white and applies the page's rotation.
        guard let data = page.thumbnail(of: size, for: .cropBox).jpegData(compressionQuality: 0.9) else {
            throw EmbeddedSearchError.message("This PDF page couldn’t be drawn.")
        }
        return data
    }
}
