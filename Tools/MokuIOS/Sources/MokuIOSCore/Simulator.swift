import Foundation

public struct Simulator: Decodable {
  public let udid: String
  public let name: String
  public let state: String
  public static func devices(_ json: String) throws -> [Simulator] {
    struct Listing: Decodable { let devices: [String: [Simulator]] }
    let listing = try JSONDecoder().decode(Listing.self, from: Data(json.utf8))
    return listing.devices.keys.filter { $0.contains(".iOS-") }.sorted {
      $0.compare($1, options: .numeric) == .orderedDescending
    }.flatMap { listing.devices[$0] ?? [] }
  }
  public static func select(_ devices: [Simulator], requested: String?) throws -> Simulator {
    if let requested {
      guard let device = devices.first(where: { $0.udid == requested }) else {
        throw CLIError("Simulator \(requested) is unavailable. Run ./moku-ios simulators.")
      }
      return device
    }
    let booted = devices.filter { $0.state == "Booted" }
    guard booted.count < 2 else {
      throw CLIError("Multiple simulators are booted; pass --simulator UDID.")
    }
    guard let device = booted.first ?? devices.first(where: { $0.name.hasPrefix("iPhone") }) else {
      throw CLIError("No iPhone simulator available. Install a runtime in Xcode.")
    }
    return device
  }
}
