import SwiftUI

/// Title, description and icon for each Rust category id.
enum CategoryInfo {
    struct Meta {
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let icon: String
    }

    static func meta(_ id: String) -> Meta {
        switch id {
        case "rust-build": return Meta(title: "Rust build", detail: "target/, rebuilt by cargo build", icon: "gearshape.2")
        case "node-deps": return Meta(title: "node_modules", detail: "Restored by npm / yarn install", icon: "shippingbox")
        case "js-build": return Meta(title: "JS build cache", detail: ".next, .nuxt, .turbo", icon: "bolt")
        case "python-cache": return Meta(title: "Python cache", detail: "__pycache__, pytest, mypy, ruff", icon: "chevron.left.forwardslash.chevron.right")
        case "python-venv": return Meta(title: "Python virtualenvs", detail: "Need pip install again after removing", icon: "cube")
        case "gradle": return Meta(title: "Gradle build", detail: "build/ and .gradle/ in projects", icon: "hammer")
        case "cocoapods": return Meta(title: "CocoaPods", detail: "Pods/, restored by pod install", icon: "shippingbox")
        case "swift-build": return Meta(title: "Swift build", detail: ".build/ in Swift packages", icon: "swift")
        case "xcode-derived": return Meta(title: "Xcode DerivedData", detail: "Rebuilt by Xcode", icon: "hammer")
        case "xcode-device-support": return Meta(title: "Device Support", detail: "Debug symbols for older iOS versions", icon: "iphone")
        case "xcode-archives": return Meta(title: "Xcode archives", detail: "Old App Store builds", icon: "archivebox")
        case "simulators": return Meta(title: "iOS simulators", detail: "Devices in Xcode's Simulator", icon: "iphone")
        case "simulator-cache": return Meta(title: "Simulator cache", detail: "CoreSimulator/Caches", icon: "iphone")
        case "android-emulators": return Meta(title: "Android emulators", detail: "AVD devices", icon: "smartphone")
        case "android-images": return Meta(title: "Android system images", detail: "Downloaded again by Android Studio", icon: "square.stack.3d.up")
        case "vms": return Meta(title: "Virtual machines", detail: "Docker, UTM, Parallels, VMware", icon: "server.rack")
        case "pkg-cache": return Meta(title: "Package caches", detail: "Homebrew, npm, pip, Cargo, Gradle…", icon: "shippingbox")
        case "app-cache": return Meta(title: "App caches", detail: "~/Library/Caches", icon: "tray.full")
        case "logs": return Meta(title: "Logs", detail: "~/Library/Logs", icon: "doc.plaintext")
        case "ios-backups": return Meta(title: "iPhone / iPad backups", detail: "Check that you don't need them", icon: "iphone")
        case "installers": return Meta(title: "Installers", detail: ".dmg, .pkg, .iso in Downloads", icon: "arrow.down.doc")
        case "trash": return Meta(title: "Trash", detail: "Files you already deleted", icon: "trash")
        default: return Meta(title: LocalizedStringKey(id), detail: "", icon: "folder")
        }
    }
}
