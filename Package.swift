// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Tami",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/smittytone/HighlighterSwift", from: "1.1.6"),
        .package(path: "SwiftTerm")
    ],
    targets: [
        .executableTarget(
            name: "Tami",
            dependencies: [
                .product(name: "Highlighter", package: "HighlighterSwift"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Tami",
            sources: [
                "main.swift",
                "AppDelegate.swift",
                "MainWindowController.swift",
                "MainSplitViewController.swift",
                "TerminalTabViewController.swift",
                "EditorViewController.swift",
                "SidebarViewController.swift",
                "TerminalViewController.swift",
                "FavoritesManager.swift"
            ],
            swiftSettings: [
                .unsafeFlags(["-swift-version", "5"])
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
