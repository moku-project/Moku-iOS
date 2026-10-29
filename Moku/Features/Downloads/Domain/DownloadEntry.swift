import Foundation

enum DownloadStatus: String {
    case queued = "Queued"
    case downloading = "Downloading"
    case failed = "Failed"
    case completed = "Completed"
}

enum DownloadsSection: String, CaseIterable, Identifiable {
    case all = "All"
    case pending = "Pending"
    case completed = "Completed"
    case failed = "Failed"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .all: "SquaresFour"
        case .pending: "Clock"
        case .completed: "CheckCircle"
        case .failed: "Warning"
        }
    }
    var emptyMessage: String { "No \(rawValue.lowercased()) downloads in this view." }
    func includes(_ entry: DownloadEntry) -> Bool {
        switch self {
        case .all: true
        case .pending: entry.status == .queued || entry.status == .downloading
        case .completed: entry.status == .completed
        case .failed: entry.status == .failed
        }
    }
}

struct DownloadEntry: Identifiable, Equatable, Sendable {
    let id: String
    let titleID: String
    let title: String
    let chapter: String
    var status: DownloadStatus
    var progress: Double = 0
    var bytes: Int64 = 0
    var completedAt: Date?
    var coverURL: URL? = nil
}

struct DownloadGroup: Identifiable {
    let id: String
    let entries: [DownloadEntry]
    var title: String { entries.first?.title ?? "" }
    var failures: Int { entries.filter { $0.status == .failed }.count }
    var active: DownloadEntry? { entries.first { $0.status == .downloading } }
}
