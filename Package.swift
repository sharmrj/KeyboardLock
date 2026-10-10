// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "KeyboardLock",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "KeyboardLock", targets: ["KeyboardLock"])
    ],
    targets: [
        .executableTarget(
            name: "KeyboardLock",
            path: "Sources/KeyboardLock"
        )
    ]
)
