// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CMDV",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CMDV", targets: ["CMDV"]),
        .library(name: "CMDVCore", targets: ["CMDVCore"])
    ],
    targets: [
        .target(
            name: "CMDVCore",
            dependencies: [],
            path: "Sources/CMDVCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        ),
        .executableTarget(
            name: "CMDV",
            dependencies: ["CMDVCore"],
            path: "Sources/CMDVApp"
        ),
        .executableTarget(
            name: "CMDVTestRunner",
            dependencies: ["CMDVCore"],
            path: "Tests/CMDVTests"
        )
    ]
)
