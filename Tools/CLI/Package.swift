// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "CLI",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "moku-ios", targets: ["CLI"])],
  targets: [
    .target(name: "CLICore"),
    .executableTarget(name: "CLI", dependencies: ["CLICore"]),
    .testTarget(name: "CLICoreTests", dependencies: ["CLICore"]),
  ],
  swiftLanguageModes: [.v5]
)
