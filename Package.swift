// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AutoClawd",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AutoClawd",
            path: "Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("CoreWLAN")
            ]
        )
    ]
)
