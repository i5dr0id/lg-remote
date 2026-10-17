// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LGRemote",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "LGRemote", targets: ["LGRemote"]),
        .library(name: "LGTVKit", targets: ["LGTVKit"]),
    ],
    targets: [
        .target(name: "LGTVKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "LGRemote",
            dependencies: ["LGTVKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
