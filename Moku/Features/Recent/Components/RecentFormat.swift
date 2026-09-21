import Foundation

enum RecentFormat {
    static func duration(_ minutes: Int) -> String {
        minutes < 1
            ? "< 1 min" : minutes < 60 ? "\(minutes) min" : "\(minutes / 60)h \(minutes % 60)m"
    }
}
