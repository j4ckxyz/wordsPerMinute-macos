// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WPMBar",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WPMBar", targets: ["WPMBar"]),
        .library(name: "WPMCore", targets: ["WPMCore"]),
    ],
    targets: [
        // Pure, UI-free logic: key classification, rolling WPM, sessions, daily stats.
        .target(name: "WPMCore"),
        // The menu bar app (SwiftUI MenuBarExtra + CGEventTap).
        .executableTarget(
            name: "WPMBar",
            dependencies: ["WPMCore"],
            linkerSettings: [
                // Embed Info.plist so even the bare binary is an LSUIElement agent.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist", "-Xlinker", "Support/Info.plist",
                ]),
            ]
        ),
        .testTarget(name: "WPMCoreTests", dependencies: ["WPMCore"]),
    ],
    swiftLanguageModes: [.v5]
)
