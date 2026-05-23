// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScripTronNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ScripTronNative", targets: ["ScripTronNative"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ScripTronNative",
            linkerSettings: [
                .unsafeFlags([
                    "-L../../target/debug",
                    "-lscriptron_ffi",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "../../target/debug"
                ])
            ]
        ),
        .testTarget(
            name: "ScripTronNativeTests",
            dependencies: ["ScripTronNative"]
        )
    ]
)
