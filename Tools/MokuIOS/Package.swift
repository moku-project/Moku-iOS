// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "MokuIOS",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "moku-ios", targets: ["MokuIOS"])],
  targets: [
    .target(name: "MokuIOSCore"),
    .executableTarget(name: "MokuIOS", dependencies: ["MokuIOSCore"]),
    .testTarget(name: "MokuIOSCoreTests", dependencies: ["MokuIOSCore"]),
  ],
  swiftLanguageModes: [.v5]
)
