// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Anasing", platforms: [.macOS(.v14)], products: [.executable(name: "Anasing", targets: ["Anasing"])], targets: [.executableTarget(name: "Anasing", swiftSettings: [.swiftLanguageMode(.v5)])])
