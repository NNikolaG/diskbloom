import Foundation

/// A disk or folder in the sidebar.
struct Place: Identifiable, Hashable {
    let url: URL
    let name: String
    let icon: String
    let isVolume: Bool

    var id: URL { url }
    var isBootVolume: Bool { isVolume && url.path == "/" }

    static func folder(_ url: URL, name: String? = nil, icon: String = "folder") -> Place {
        Place(url: url, name: name ?? FileManager.default.displayName(atPath: url.path), icon: icon, isVolume: false)
    }

    static var home: Place {
        .folder(FileManager.default.homeDirectoryForCurrentUser, name: "Home", icon: "house")
    }

    static var bootVolume: Place {
        Place(url: URL(fileURLWithPath: "/"), name: BootVolume.name, icon: "internaldrive", isVolume: true)
    }
}
