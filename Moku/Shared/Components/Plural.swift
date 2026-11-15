import Foundation

/// "1 title", "3 titles": a count with the noun in agreement.
func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count.formatted()) \(count == 1 ? singular : plural ?? singular + "s")"
}
