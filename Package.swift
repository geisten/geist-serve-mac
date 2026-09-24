// swift-tools-version: 5.9
// Geist — menu bar app that runs geist-serve. Built with `make`, which calls
// swift build and then scripts/bundle.sh to assemble Geist.app; Xcode can
// open this package directly for development.
import PackageDescription

let package = Package(
    name: "Geist",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Geist",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Geist",
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])],
            // Sparkle.framework lives in Contents/Frameworks of the bundle.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
    ]
)
