// swift-tools-version: 5.9
import PackageDescription
import Foundation

let locationInfo = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Configuration/LocationUsage.plist").path

let package = Package(
    name: "LockShift",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LockShift",
            path: "Sources/LockShift",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", locationInfo])
            ]
        ),
        .testTarget(name: "LockShiftTests", dependencies: ["LockShift"])
    ]
)
