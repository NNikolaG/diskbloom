// swift-tools-version:5.9
// Pre `swift build` pokreni ./build.sh: on pravi Rust xcframework i generise Swift veze.
import PackageDescription

let package = Package(
    name: "Diskbloom",
    platforms: [.macOS(.v13)],
    targets: [
        // Rust staticka biblioteka + C header (generise build.sh)
        .binaryTarget(name: "diskbloom_ffiFFI", path: "build/diskbloom_ffiFFI.xcframework"),
        // Swift veze koje generise uniffi-bindgen (generise build.sh)
        .target(
            name: "DiskbloomFFI",
            dependencies: ["diskbloom_ffiFFI"],
            path: "Sources/DiskbloomFFI",
            linkerSettings: [.linkedLibrary("iconv")]  // Rust std na macOS-u
        ),
        .executableTarget(name: "Diskbloom", dependencies: ["DiskbloomFFI"], path: "Sources/Diskbloom"),
    ]
)
