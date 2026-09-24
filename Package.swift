// swift-tools-version: 5.9
// Geist — menu bar app that runs geist-serve. Built with `make`, which calls
// swift build and then scripts/bundle.sh to assemble Geist.app; Xcode can
// open this package directly for development.
import PackageDescription

let package = Package(
    name: "Geist",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Geist",
            path: "Sources/Geist",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
    ]
)
