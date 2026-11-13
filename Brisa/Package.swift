// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Brisa",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrisaCore", targets: ["BrisaCore"]),
        .executable(name: "BrisaApp", targets: ["BrisaApp"]),
        .executable(name: "brisa", targets: ["BrisaCLI"]),
        .executable(name: "brisa-mcp", targets: ["BrisaMCP"])
    ],
    targets: [
        .target(name: "BrisaCore", resources: [.process("Resources")]),
        .executableTarget(name: "BrisaApp", dependencies: ["BrisaCore"], resources: [.process("Resources")]),
        .executableTarget(name: "BrisaCLI", dependencies: ["BrisaCore"]),
        .executableTarget(name: "BrisaMCP", dependencies: ["BrisaCore"]),
        .testTarget(name: "BrisaCoreTests", dependencies: ["BrisaCore"]),
        .testTarget(name: "BrisaAppTests", dependencies: ["BrisaApp"])
    ],
    swiftLanguageModes: [.v5]
)
