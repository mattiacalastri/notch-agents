// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchAgenti",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: which sessions are alive, what state, what the notch says.
        .target(name: "NotchAgentiCore"),
        // The notch itself (AppKit panel + SwiftUI view).
        .executableTarget(name: "NotchAgenti", dependencies: ["NotchAgentiCore"]),
        .testTarget(name: "NotchAgentiCoreTests", dependencies: ["NotchAgentiCore"]),
    ]
)
