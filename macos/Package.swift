// swift-tools-version:5.9
// Pre `swift build` pokreni ./build.sh: on pravi Rust biblioteku i generise Swift veze.
import Foundation
import PackageDescription

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Diskbloom",
    platforms: [.macOS(.v13)],
    targets: [
        // C header + modulemap za Rust biblioteku (generise build.sh u build/ffi)
        .systemLibrary(name: "diskbloom_ffiFFI", path: "build/ffi"),
        // Swift veze koje generise uniffi-bindgen
        .target(
            name: "DiskbloomFFI",
            dependencies: ["diskbloom_ffiFFI"],
            path: "Sources/DiskbloomFFI",
            linkerSettings: [
                .unsafeFlags(["-L", here + "/build/lib"]),
                .linkedLibrary("diskbloom_ffi"),
                .linkedLibrary("iconv"),  // Rust std na macOS-u
            ]
        ),
        .executableTarget(name: "Diskbloom", dependencies: ["DiskbloomFFI"], path: "Sources/Diskbloom"),
    ]
)
